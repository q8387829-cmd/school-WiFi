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
        $verifiedCredential = Read-CampusCredential $temporaryPath
        $verifiedCredential.Password.Dispose()
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
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('CampusReconnect/2.0')
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
        $requestTimer = [Diagnostics.Stopwatch]::StartNew()
        try { $response = $Client.GetAsync($uri).GetAwaiter().GetResult() }
        catch {
            if ($requestTimer.Elapsed.TotalSeconds -gt 15) { Throw-CampusFault 'ResumeDetected' $stage }
            throw
        }
        if (-not $response.IsSuccessStatusCode) {
            $status = [int]$response.StatusCode
            $code = if ($status -ge 300 -and $status -lt 400) { 'UnexpectedRedirect' }
                elseif ($status -in @(401, 403)) { 'HttpAccessDenied' }
                elseif ($status -eq 407) { 'ProxyRequired' }
                elseif ($status -eq 429) { 'RateLimited' }
                elseif ($status -ge 500) { 'ServerError' }
                elseif ($status -eq 404) { 'EndpointNotFound' }
                else { 'HttpError' }
            $retryAfter = 60
            if ($status -eq 429 -and $null -ne $response.Headers.RetryAfter) {
                if ($null -ne $response.Headers.RetryAfter.Delta) { $retryAfter = [int][Math]::Ceiling($response.Headers.RetryAfter.Delta.TotalSeconds) }
                elseif ($null -ne $response.Headers.RetryAfter.Date) { $retryAfter = [int][Math]::Ceiling(($response.Headers.RetryAfter.Date - [datetimeoffset]::UtcNow).TotalSeconds) }
            }
            Throw-CampusFault $code $stage $status -RetryAfterSeconds ([Math]::Max(60, $retryAfter))
        }
        if ($requestTimer.Elapsed.TotalSeconds -gt 15) { Throw-CampusFault 'ResumeDetected' $stage }
        $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        try { return ConvertFrom-CampusJsonp ([Text.Encoding]::UTF8.GetString($bytes)) }
        catch { Throw-CampusFault 'InvalidResponse' $stage }
    } catch {
        # Exception messages from HTTP libraries may include a password-bearing URL.
        $fault = Get-CampusFault $_
        Throw-CampusFault $fault.Code $stage $fault.HttpStatus -RetryAfterSeconds $fault.RetryAfterSeconds
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

function Get-CampusSnapshot($Client, $Network = $null, $StopSignal = $null) {
    if ($null -ne $StopSignal -and $StopSignal.WaitOne(0)) { return $null }
    if ($null -eq $Network) { $Network = Get-CampusNetworkContext }
    if (-not $Network.Known) { return New-CampusSnapshot 'Unknown' 'LocalInfoUnavailable' $Network -Stage 'LocalNetwork' }
    if (-not $Network.HasLink) { return New-CampusSnapshot 'Unknown' 'NoLocalLink' $Network -Stage 'LocalNetwork' }
    if (-not $Network.HasIpv4) { return New-CampusSnapshot 'Unknown' 'NoIpv4' $Network -Stage 'LocalNetwork' }
    if ($null -ne $StopSignal -and $StopSignal.WaitOne(0)) { return $null }
    try {
        $core = Invoke-CampusJsonp $Client 'http://10.10.102.50/drcom/chkstatus' @{}
        if ($null -ne $StopSignal -and $StopSignal.WaitOne(0)) { return $null }
        $terminal = Get-CampusTerminal $core $Network
        $config = Get-CampusConfig $Client $terminal
        if ($null -ne $StopSignal -and $StopSignal.WaitOne(0)) { return $null }
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
        return New-CampusSnapshot 'Unknown' $fault.Code $Network -Stage $fault.Stage -HttpStatus $fault.HttpStatus -RetryAfterSeconds $fault.RetryAfterSeconds
    }
}

. (Join-Path $PSScriptRoot 'CampusNetwork.Retry.ps1')

function ConvertFrom-CampusLoginReply($Reply) {
    if (([string](Get-CampusField $Reply 'result')) -in @('1', 'ok')) {
        return [pscustomobject]@{ Accepted = $true; Stop = $false; Kind = 'Accepted'; Reason = '' }
    }
    # ret_code=1 and isolated password/captcha keywords are not credential errors.
    # Return fixed diagnostics only: msg/msga can contain private data.
    $message = ([string](Get-CampusField $Reply 'msg') + ' ' + [string](Get-CampusField $Reply 'msga'))
    $kind = 'Unclassified'; $hold = $false
    $reason = '[LoginUnclassified/Login] 认证端未说明可识别的拒绝原因。'
    if ($message -match '(?:输入|提供|需要|缺少|请填写).{0,6}(?:验证码|校验码)|(?:验证码|校验码)\s*(?:有误|错误|不正确|无效|过期|为空|校验失败)|\b(?:invalid|incorrect|wrong|expired|missing|required)\s+captcha\b|\bcaptcha\s+(?:(?:is|has)\s+)?(?:required|invalid|incorrect|wrong|expired|missing)\b') {
        $kind = 'Challenge'; $hold = $true; $reason = '[LoginChallenge/Login] 认证端提示验证码问题，已暂停提交，请在网页登录。'
    } elseif ($message -match '(?:密码|口令|账[号户]|帐[号户]|用户(?:名)?)\s*(?:输入)?\s*(?:有误|错误|不正确|无效|不存在|不对|不匹配|为空|校验失败)|\b(?:invalid|incorrect|wrong|bad|unknown)\s+(?:login\s+)?(?:password|user(?:\s*name)?|account|credentials?)\b|\b(?:password|user\s*name|account|credentials?)\s+(?:(?:is|are)\s+)?(?:incorrect|wrong|invalid|not found|does not exist|error)\b') {
        $kind = 'Credential'; $hold = $true; $reason = '[CredentialRejected/Login] 认证端明确提示账号或密码错误，已暂停提交，请检查保存的账号。'
    } elseif ($message -match '(?:账[号户]|帐[号户]|用户)(?:已|被|已被)?(?:锁定|禁用|冻结|停用|欠费|过期)|\baccount\s+(?:(?:is|was)\s+)?(?:locked|disabled|expired)\b') {
        $kind = 'Account'; $hold = $true; $reason = '[AccountRestricted/Login] 认证端提示账号受限，已暂停提交，请检查账号状态。'
    } elseif ($message -match '繁忙|超时|稍后再?试|稍后重试|正在认证|认证中|已经?在线|服务(?:器)?(?:暂时)?(?:不可用|异常)|系统忙|数据库|\b(?:busy|timeout|unavailable|already online|try again later|timed out|internal server error|server error|database)\b') {
        $kind = 'Transient'; $reason = '[LoginTemporary/Login] 认证端暂未完成登录，将复查状态并按间隔重试。'
    } elseif ($message -match '验证码|校验码|\bcaptcha\b') {
        $kind = 'Challenge'; $hold = $true; $reason = '[LoginChallenge/Login] 认证端提示验证码问题，已暂停提交，请在网页登录。'
    }
    return [pscustomobject]@{ Accepted = $false; Stop = $hold; Kind = $kind; Reason = $reason }
}

function Invoke-CampusLogin($Client, $Snapshot, [pscredential]$Credential, $Network = $null, $StopSignal = $null) {
    if ($null -ne $StopSignal -and $StopSignal.WaitOne(0)) { return $null }
    if ((Get-CampusField $Snapshot 'State' 'Unknown') -ne 'Offline') {
        $diagnostic = New-CampusSnapshot 'Unknown' 'AuthenticationUnconfirmed' (Get-CampusField $Snapshot 'Network' $null) -Stage 'Login'
        return [pscustomobject]@{ Accepted = $false; Stop = $false; Kind = 'LocalNetwork'; Code = 'AuthenticationUnconfirmed'; Submitted = $false; Reason = (Format-CampusDiagnostic $diagnostic) }
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
    $submitted = $false
    try {
        # A status request can take several seconds. Recheck the local interface
        # immediately before using the saved password after a DHCP/VPN change.
        if ($null -eq $Network) { $Network = Get-CampusNetworkContext }
        if (-not $Network.Known) { Throw-CampusFault 'LocalInfoUnavailable' 'LocalNetwork' }
        if (-not $Network.HasLink) { Throw-CampusFault 'NoLocalLink' 'LocalNetwork' }
        if (-not $Network.HasIpv4) { Throw-CampusFault 'NoIpv4' 'LocalNetwork' }
        $currentTerminal = Get-CampusTerminal ([pscustomobject]@{ v4ip = $Snapshot.Terminal.Ip }) $Network
        if ($currentTerminal.Mac -ne $Snapshot.Terminal.Mac) { Throw-CampusFault 'LocalAddressChanged' 'LocalNetwork' }
        if ($null -ne $StopSignal -and $StopSignal.WaitOne(0)) { return $null }
        $plainPassword = $Credential.GetNetworkCredential().Password
        $data = @{
            login_method = (Get-CampusField $config 'login_method'); user_account = $prefix + $Credential.UserName
            user_password = $plainPassword; wlan_user_ip = $Snapshot.Terminal.Ip
            wlan_user_ipv6 = $Snapshot.Terminal.Ipv6; wlan_user_mac = $Snapshot.Terminal.Mac
            wlan_ac_ip = ''; wlan_ac_name = ''; terminal_type = 1; lang = 'zh-cn'
        }
        $submitted = $true
        $reply = Invoke-CampusJsonp $Client 'http://10.10.102.50:801/eportal/portal/login' $data
        $result = ConvertFrom-CampusLoginReply $reply
        $result | Add-Member NoteProperty Submitted $true
        return $result
    } catch {
        $fault = Get-CampusFault $_
        $diagnostic = New-CampusSnapshot 'Unknown' $fault.Code (Get-CampusField $Snapshot 'Network' $null) -Stage $fault.Stage -HttpStatus $fault.HttpStatus
        return [pscustomobject]@{
            Accepted = $false; Stop = $false; Kind = 'Transient'; Code = $fault.Code; Stage = $fault.Stage
            HttpStatus = $fault.HttpStatus; RetryAfterSeconds = $fault.RetryAfterSeconds
            Submitted = $submitted; Reason = (Format-CampusDiagnostic $diagnostic)
        }
    } finally {
        if ($null -ne $data) { $data['user_password'] = '' }
        $plainPassword = $null
    }
}
