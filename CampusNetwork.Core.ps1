Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'CampusNetwork.Diagnostics.ps1')

function Read-CampusCredential([string]$Path) {
    try {
        $credential = Import-Clixml -LiteralPath $Path -ErrorAction Stop
        if ($credential -isnot [pscredential] -or [string]::IsNullOrWhiteSpace($credential.UserName) -or
            $credential.Password.Length -eq 0) { throw 'Invalid credential record' }
        return $credential
    } catch {
        throw '账号记录缺失、无效或无法解密，请用当前 Windows 用户重新运行首次配置。'
    }
}

function Save-CampusCredential([string]$Path, [pscredential]$Credential) {
    if ([string]::IsNullOrWhiteSpace($Credential.UserName) -or $Credential.Password.Length -eq 0) {
        throw '账号和密码不能为空。'
    }
    $temporaryPath = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $Credential | Export-Clixml -LiteralPath $temporaryPath -Encoding UTF8 -ErrorAction Stop
        [void](Read-CampusCredential $temporaryPath)
        if (Test-Path -LiteralPath $Path) {
            [IO.File]::Replace($temporaryPath, $Path, [NullString]::Value)
        } else {
            [IO.File]::Move($temporaryPath, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
}

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
    if ($Endpoint -notin $allowed) { Throw-CampusFault 'EndpointNotAllowed' 'Request' }
    $stage = switch ($Endpoint) {
        'http://10.10.102.50/drcom/chkstatus' { 'KernelStatus' }
        'http://10.10.102.50:801/eportal/portal/page/loadConfig' { 'PortalConfig' }
        'http://10.10.102.50:801/eportal/portal/online_list' { 'SessionList' }
        default { 'Login' }
    }
    $params = [ordered]@{ callback = 'campusCallback'; jsVersion = '4.X' }
    foreach ($key in $Data.Keys) { $params[$key] = $Data[$key] }
    $response = $null
    try {
        $uri = $Endpoint + '?' + (ConvertTo-CampusQuery $params)
        $response = $Client.GetAsync($uri).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            $status = [int]$response.StatusCode
            $code = if ($status -ge 300 -and $status -lt 400) { 'UnexpectedRedirect' }
                elseif ($status -in @(401, 403)) { 'HttpAccessDenied' }
                elseif ($status -eq 407) { 'ProxyRequired' }
                elseif ($status -eq 429) { 'RateLimited' }
                elseif ($status -ge 500) { 'ServerError' }
                elseif ($status -eq 404) { 'EndpointNotFound' }
                else { 'HttpError' }
            Throw-CampusFault $code $stage $status
        }
        $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        try { return ConvertFrom-CampusJsonp ([Text.Encoding]::UTF8.GetString($bytes)) }
        catch { Throw-CampusFault 'InvalidResponse' $stage }
    } catch {
        # Exception messages from HTTP libraries may include a password-bearing URL.
        $fault = Get-CampusFault $_
        Throw-CampusFault $fault.Code $stage $fault.HttpStatus
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

function Get-CampusTerminal($CoreStatus, $Network = $null) {
    $ip = ''
    foreach ($name in @('v4ip', 'v46ip', 'ss5')) {
        $candidate = [string](Get-CampusField $CoreStatus $name)
        if ($candidate -match '^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { $ip = $candidate; break }
    }
    if (-not $ip) { Throw-CampusFault 'PortalAddressMissing' 'LocalNetwork' }
    if ($null -eq $Network) { $Network = Get-CampusNetworkContext }
    foreach ($adapter in $Network.Adapters) {
        if (-not $adapter.IsUp -or -not $adapter.IsLocal -or $ip -notin $adapter.Ipv4 -or $adapter.Mac -notmatch '^[0-9A-Fa-f]{12}$') { continue }
        $v6 = [string](Get-CampusField $CoreStatus 'myv6ip')
        if ($v6 -eq '::') { $v6 = '' }
        return [pscustomobject]@{ Ip = $ip; Mac = $adapter.Mac; Ipv6 = $v6 }
    }
    Throw-CampusFault 'LocalAddressChanged' 'LocalNetwork'
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
        Throw-CampusFault 'ConfigUnavailable' 'PortalConfig'
    }
    return $config
}

function Get-CampusSnapshot($Client, $Network = $null) {
    if ($null -eq $Network) { $Network = Get-CampusNetworkContext }
    if (-not $Network.Known) { return New-CampusSnapshot 'Unknown' 'LocalInfoUnavailable' $Network -Stage 'LocalNetwork' }
    if (-not $Network.HasLink) { return New-CampusSnapshot 'Unknown' 'NoLocalLink' $Network -Stage 'LocalNetwork' }
    if (-not $Network.HasIpv4) { return New-CampusSnapshot 'Unknown' 'NoIpv4' $Network -Stage 'LocalNetwork' }
    try {
        $core = Invoke-CampusJsonp $Client 'http://10.10.102.50/drcom/chkstatus' @{}
        $terminal = Get-CampusTerminal $core $Network
        $config = Get-CampusConfig $Client $terminal
        if ((Get-CampusField $config 'login_method' -1) -notin @(1, 9) -or
            (Get-CampusField $config 'en_md5' 0) -ne 0 -or (Get-CampusField $config 'password_cut' 0) -ne 0) {
            Throw-CampusFault 'UnsupportedProtocol' 'PortalConfig'
        }
        $onlineMethod = [string](Get-CampusField $config 'check_online_method' -1)
        if ($onlineMethod -notin @('0', '1')) { Throw-CampusFault 'UnsupportedProtocol' 'PortalConfig' }
        if ($onlineMethod -eq '1') {
            # This portal checks the RADIUS session list, rather than the Wi-Fi icon.
            $ipNumber = ConvertTo-CampusIpNumber $terminal.Ip
            $reply = Invoke-CampusJsonp $Client 'http://10.10.102.50:801/eportal/portal/online_list' @{
                user_account = ''; user_password = ''; wlan_user_mac = $terminal.Mac
                wlan_user_ip = $ipNumber; curr_user_ip = $ipNumber
            }
            $result = [string](Get-CampusField $reply 'result' '-1')
            if ($result -eq '1' -and ($null -eq $reply.PSObject.Properties['list'] -or $reply.list -isnot [array])) {
                Throw-CampusFault 'InvalidResponse' 'SessionList'
            }
            if ($result -eq '0' -and [string](Get-CampusField $reply 'msg') -match '服务器异常|系统繁忙|查询失败|数据库|超时|服务不可用|internal|timeout|busy|unavailable') {
                Throw-CampusFault 'ServerError' 'SessionList'
            }
            $sessions = @(Get-CampusField $reply 'list' @())
            if ($result -eq '0' -and $sessions.Count -gt 0) { Throw-CampusFault 'InvalidResponse' 'SessionList' }
            $owned = @($sessions | Where-Object { (Get-CampusField $_ 'online_ip') -eq $terminal.Ip })
            if ($result -eq '1' -and $owned.Count -gt 0) { $state = 'Online' }
            elseif ($result -eq '0' -or ($result -eq '1' -and $sessions.Count -eq 0)) { $state = 'Offline' }
            elseif ($result -eq '1' -and $sessions.Count -gt 0) { Throw-CampusFault 'SessionMismatch' 'SessionList' }
            else { Throw-CampusFault 'InvalidResponse' 'SessionList' }
        } else {
            $result = [string](Get-CampusField $core 'result' '-1')
            if ($result -eq '1') { $state = 'Online' }
            elseif ($result -eq '0') { $state = 'Offline' }
            else { Throw-CampusFault 'InvalidResponse' 'KernelStatus' }
        }
        $code = if ($state -eq 'Online') { 'Authenticated' } else { 'NotAuthenticated' }
        return New-CampusSnapshot $state $code $Network $terminal $config
    } catch {
        $fault = Get-CampusFault $_
        return New-CampusSnapshot 'Unknown' $fault.Code $Network -Stage $fault.Stage -HttpStatus $fault.HttpStatus
    }
}

function New-CampusMonitorState {
    return [pscustomobject]@{ Failures = 0; NextAttempt = [datetime]::MinValue }
}

function Get-CampusAction($State, [string]$Status, [datetime]$Now) {
    if ($Status -eq 'Online') {
        $State.Failures = 0; $State.NextAttempt = [datetime]::MinValue
        return 'Wait'
    }
    if ($Status -eq 'Offline' -and $Now -ge $State.NextAttempt) { return 'Login' }
    return 'Wait'
}

function Set-CampusFailure($State, [datetime]$Now) {
    $State.Failures++
    $delay = if ($State.Failures -ge 3) { 900 } else { 60 * [Math]::Pow(2, $State.Failures - 1) }
    $State.NextAttempt = $Now.AddSeconds($delay)
    return [int]$delay
}

function Invoke-CampusLogin($Client, $Snapshot, [pscredential]$Credential, $Network = $null) {
    if ((Get-CampusField $Snapshot 'State' 'Unknown') -ne 'Offline') {
        $diagnostic = New-CampusSnapshot 'Unknown' 'AuthenticationUnconfirmed' (Get-CampusField $Snapshot 'Network' $null) -Stage 'Login'
        return [pscustomobject]@{ Accepted = $false; Stop = $false; Reason = (Format-CampusDiagnostic $diagnostic) }
    }
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
        # A status request can take several seconds. Recheck the local interface
        # immediately before using the saved password after a DHCP/VPN change.
        if ($null -eq $Network) { $Network = Get-CampusNetworkContext }
        if (-not $Network.Known) { Throw-CampusFault 'LocalInfoUnavailable' 'LocalNetwork' }
        if (-not $Network.HasLink) { Throw-CampusFault 'NoLocalLink' 'LocalNetwork' }
        if (-not $Network.HasIpv4) { Throw-CampusFault 'NoIpv4' 'LocalNetwork' }
        $currentTerminal = Get-CampusTerminal ([pscustomobject]@{ v4ip = $Snapshot.Terminal.Ip }) $Network
        if ($currentTerminal.Mac -ne $Snapshot.Terminal.Mac) { Throw-CampusFault 'LocalAddressChanged' 'LocalNetwork' }
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
        $fault = Get-CampusFault $_
        $diagnostic = New-CampusSnapshot 'Unknown' $fault.Code (Get-CampusField $Snapshot 'Network' $null) -Stage $fault.Stage -HttpStatus $fault.HttpStatus
        return [pscustomobject]@{ Accepted = $false; Stop = $false; Reason = (Format-CampusDiagnostic $diagnostic) }
    } finally {
        if ($null -ne $data) { $data['user_password'] = '' }
        $plainPassword = $null
    }
}
