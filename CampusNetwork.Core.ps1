Set-StrictMode -Version 2.0

function New-CampusHttpClient {
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.UseProxy = $false
    $handler.AllowAutoRedirect = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(10)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('CampusReconnect/1.0')
    return $client
}

function Get-CampusField($Object, [string]$Name, $Default = '') {
    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) {
        return $Object.$Name
    }
    return $Default
}

function ConvertFrom-CampusJsonp([string]$Text) {
    # Parse data only. Never execute JavaScript returned by the portal.
    $match = [regex]::Match($Text, '^\s*campusCallback\s*\(\s*(\{[\s\S]*\})\s*\)\s*;?\s*$')
    if (-not $match.Success) { throw '认证接口返回格式异常。' }
    return ($match.Groups[1].Value | ConvertFrom-Json -ErrorAction Stop)
}

function ConvertTo-CampusQuery([System.Collections.IDictionary]$Data) {
    $parts = foreach ($key in $Data.Keys) {
        [uri]::EscapeDataString([string]$key) + '=' + [uri]::EscapeDataString([string]$Data[$key])
    }
    return ($parts -join '&')
}

function Invoke-CampusJsonp($Client, [string]$Endpoint, [System.Collections.IDictionary]$Data) {
    $allowed = @(
        'http://10.10.102.50/drcom/chkstatus',
        'http://10.10.102.50:801/eportal/portal/page/loadConfig',
        'http://10.10.102.50:801/eportal/portal/online_list',
        'http://10.10.102.50:801/eportal/portal/login'
    )
    if ($Endpoint -notin $allowed) { throw '不允许访问未知认证接口。' }
    $params = [ordered]@{ callback = 'campusCallback'; jsVersion = '4.X' }
    foreach ($key in $Data.Keys) { $params[$key] = $Data[$key] }
    $response = $null
    try {
        $uri = $Endpoint + '?' + (ConvertTo-CampusQuery $params)
        $response = $Client.GetAsync($uri).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) { throw '请求未成功。' }
        $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        return ConvertFrom-CampusJsonp ([Text.Encoding]::UTF8.GetString($bytes))
    } catch {
        # Exception messages from HTTP libraries may include a password-bearing URL.
        throw '校园网接口不可用或返回格式异常。'
    } finally {
        if ($null -ne $response) { $response.Dispose() }
        $uri = $null
    }
}

function ConvertTo-CampusIpNumber([string]$Ip) {
    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($Ip, [ref]$parsed) -or
        $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw '无法识别本机 IPv4 地址。'
    }
    $b = $parsed.GetAddressBytes()
    return ([uint64]$b[0] * 16777216 + [uint64]$b[1] * 65536 + [uint64]$b[2] * 256 + $b[3])
}

function Get-CampusTerminal($CoreStatus) {
    $ip = ''
    foreach ($name in @('v4ip', 'v46ip', 'ss5')) {
        $candidate = [string](Get-CampusField $CoreStatus $name)
        if ($candidate -match '^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { $ip = $candidate; break }
    }
    if (-not $ip) { throw '认证接口未提供本机地址，等待网络恢复。' }
    foreach ($adapter in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($adapter.OperationalStatus -ne [Net.NetworkInformation.OperationalStatus]::Up) { continue }
        foreach ($address in $adapter.GetIPProperties().UnicastAddresses) {
            if ($address.Address.ToString() -ne $ip) { continue }
            $mac = $adapter.GetPhysicalAddress().ToString()
            if ($mac -notmatch '^[0-9A-Fa-f]{12}$') { continue }
            $v6 = [string](Get-CampusField $CoreStatus 'myv6ip')
            if ($v6 -eq '::') { $v6 = '' }
            return [pscustomobject]@{ Ip = $ip; Mac = $mac.ToUpperInvariant(); Ipv6 = $v6 }
        }
    }
    throw '本机网卡地址与认证接口不一致，等待校园网连接。'
}

function Get-CampusConfig($Client, $Terminal) {
    $encodedIp = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Terminal.Ip))
    $reply = Invoke-CampusJsonp $Client 'http://10.10.102.50:801/eportal/portal/page/loadConfig' @{
        program_index = ''; wlan_vlan_id = 0; wlan_user_ip = $encodedIp
        wlan_user_ipv6 = ''; wlan_user_ssid = ''; wlan_user_areaid = ''
        wlan_ac_ip = ''; wlan_ap_mac = ''; gw_id = '000000000000'
    }
    $config = Get-CampusField $reply 'data' $null
    if ((Get-CampusField $reply 'code' 0) -ne 1 -or $null -eq $config) {
        throw '无法读取校园网认证配置。'
    }
    return $config
}

function Get-CampusSnapshot($Client) {
    try {
        $core = Invoke-CampusJsonp $Client 'http://10.10.102.50/drcom/chkstatus' @{}
        $terminal = Get-CampusTerminal $core
        $config = Get-CampusConfig $Client $terminal
        if ((Get-CampusField $config 'check_online_method' 0) -eq 1) {
            # This portal checks the RADIUS session list, rather than the Wi-Fi icon.
            $ipNumber = ConvertTo-CampusIpNumber $terminal.Ip
            $reply = Invoke-CampusJsonp $Client 'http://10.10.102.50:801/eportal/portal/online_list' @{
                user_account = ''; user_password = ''; wlan_user_mac = $terminal.Mac
                wlan_user_ip = $ipNumber; curr_user_ip = $ipNumber
            }
            $result = [string](Get-CampusField $reply 'result' '-1')
            if ($result -eq '1' -and ($null -eq $reply.PSObject.Properties['list'] -or $null -eq $reply.list)) {
                throw '在线接口缺少会话列表。'
            }
            $sessions = @(Get-CampusField $reply 'list' @())
            $owned = @($sessions | Where-Object { (Get-CampusField $_ 'online_ip') -eq $terminal.Ip })
            if ($result -eq '1' -and $owned.Count -gt 0) { $state = 'Online' }
            elseif ($result -eq '0' -or ($result -eq '1' -and $sessions.Count -eq 0)) { $state = 'Offline' }
            else { throw '在线状态不明确。' }
        } else {
            $result = [string](Get-CampusField $core 'result' '-1')
            if ($result -eq '1') { $state = 'Online' }
            elseif ($result -eq '0') { $state = 'Offline' }
            else { throw '在线状态不明确。' }
        }
        return [pscustomobject]@{ State = $state; Terminal = $terminal; Config = $config }
    } catch {
        return [pscustomobject]@{ State = 'Unknown'; Terminal = $null; Config = $null }
    }
}

function New-CampusMonitorState {
    return [pscustomobject]@{ OfflineCount = 0; Failures = 0; NextAttempt = [datetime]::MinValue }
}

function Get-CampusAction($State, [string]$Status, [datetime]$Now) {
    if ($Status -eq 'Online') {
        $State.OfflineCount = 0; $State.Failures = 0; $State.NextAttempt = [datetime]::MinValue
        return 'Wait'
    }
    if ($Status -ne 'Offline') { $State.OfflineCount = 0; return 'Wait' }
    $State.OfflineCount = [Math]::Min(2, $State.OfflineCount + 1)
    if ($State.OfflineCount -ge 2 -and $Now -ge $State.NextAttempt) { return 'Login' }
    return 'Wait'
}

function Set-CampusFailure($State, [datetime]$Now) {
    $State.Failures++
    $delay = if ($State.Failures -ge 3) { 900 } else { 60 * [Math]::Pow(2, $State.Failures - 1) }
    $State.NextAttempt = $Now.AddSeconds($delay)
    $State.OfflineCount = 0
    return [int]$delay
}

function Invoke-CampusLogin($Client, $Snapshot, [pscredential]$Credential) {
    $config = $Snapshot.Config
    # Support only the observed portal protocol, and reject changes requiring MD5/captcha flows.
    if ((Get-CampusField $config 'login_method' -1) -notin @(1, 9) -or
        (Get-CampusField $config 'en_md5' 0) -ne 0 -or
        (Get-CampusField $config 'password_cut' 0) -ne 0) {
        return [pscustomobject]@{ Accepted = $false; Stop = $true; Reason = '认证配置已变化，请使用网页登录并重新检查工具。' }
    }
    $prefix = ''
    if ((Get-CampusField $config 'account_prefix' 0) -eq 1) {
        $prefix = if ((Get-CampusField $config 'custom_perceive' 0) -eq 1) { ',b,' } else { ',0,' }
    }
    $plainPassword = $null
    $data = $null
    try {
        $plainPassword = $Credential.GetNetworkCredential().Password
        $data = @{
            login_method = (Get-CampusField $config 'login_method'); user_account = $prefix + $Credential.UserName
            user_password = $plainPassword; wlan_user_ip = $Snapshot.Terminal.Ip
            wlan_user_ipv6 = $Snapshot.Terminal.Ipv6; wlan_user_mac = $Snapshot.Terminal.Mac
            wlan_ac_ip = ''; wlan_ac_name = ''; terminal_type = 1; lang = 'zh-cn'
        }
        $reply = Invoke-CampusJsonp $Client 'http://10.10.102.50:801/eportal/portal/login' $data
        $accepted = ([string](Get-CampusField $reply 'result')) -in @('1', 'ok')
        $message = [string](Get-CampusField $reply 'msg')
        $badCredential = -not $accepted -and ((Get-CampusField $reply 'ret_code' -1) -eq 1 -or
            $message -match '密码.*(错|不正确|不对)|账号.*(不存在|错误|不正确)|password|captcha|验证码')
        $reason = if ($badCredential) { '需要检查账号、密码或验证码；已停止自动提交，请手动登录或重新配置。' } else { '登录未成功，稍后再试。' }
        return [pscustomobject]@{ Accepted = $accepted; Stop = $badCredential; Reason = $reason }
    } catch {
        return [pscustomobject]@{ Accepted = $false; Stop = $false; Reason = '登录接口暂时不可用，稍后再试。' }
    } finally {
        if ($null -ne $data) { $data['user_password'] = '' }
        $plainPassword = $null
    }
}
