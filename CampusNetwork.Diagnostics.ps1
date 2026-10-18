# Diagnostics contain fixed messages only; never include credentials, request URLs or raw responses.
function Throw-CampusFault([string]$Code, [string]$Stage, [int]$HttpStatus = 0) {
    $failure = New-Object System.Exception('Campus network check failed: ' + $Code)
    $failure.Data['CampusCode'] = $Code
    $failure.Data['CampusStage'] = $Stage
    $failure.Data['CampusHttpStatus'] = $HttpStatus
    throw $failure
}

function Get-CampusFault($ErrorObject) {
    $exception = if ($ErrorObject -is [Management.Automation.ErrorRecord]) { $ErrorObject.Exception } else { $ErrorObject }
    $code = 'ConnectionFailed'
    while ($null -ne $exception) {
        if ($exception.Data.Contains('CampusCode')) {
            return [pscustomobject]@{ Code = [string]$exception.Data['CampusCode']; Stage = [string]$exception.Data['CampusStage']; HttpStatus = [int]$exception.Data['CampusHttpStatus'] }
        }
        if ($exception -is [OperationCanceledException] -or $exception -is [TimeoutException]) { $code = 'RequestTimeout' }
        if ($exception -is [UnauthorizedAccessException] -or $exception -is [Security.SecurityException]) { $code = 'AccessDenied' }
        if ($exception -is [Net.Sockets.SocketException]) {
            $code = switch ([string]$exception.SocketErrorCode) {
                'AccessDenied' { 'AccessDenied' }
                'TimedOut' { 'RequestTimeout' }
                'ConnectionRefused' { 'ConnectionRefused' }
                'NetworkUnreachable' { 'HostUnreachable' }
                'HostUnreachable' { 'HostUnreachable' }
                'NetworkDown' { 'HostUnreachable' }
                'AddressNotAvailable' { 'LocalAddressChanged' }
                default { 'ConnectionFailed' }
            }
        }
        $exception = $exception.InnerException
    }
    return [pscustomobject]@{ Code = $code; Stage = ''; HttpStatus = 0 }
}

function Get-CampusAdapters {
    foreach ($adapter in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        $properties = $adapter.GetIPProperties()
        $ipv4 = @($properties.UnicastAddresses | Where-Object {
            $_.Address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and
            $_.Address.ToString() -notmatch '^(0\.|127\.|169\.254\.)'
        } | ForEach-Object { $_.Address.ToString() })
        $gateways = @($properties.GatewayAddresses | Where-Object {
            $_.Address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and $_.Address.ToString() -ne '0.0.0.0'
        } | ForEach-Object { $_.Address.ToString() })
        $tunnel = $adapter.NetworkInterfaceType -eq [Net.NetworkInformation.NetworkInterfaceType]::Tunnel -or
            ($adapter.Name + ' ' + $adapter.Description) -match '(?i)sing[- ]tun|wintun|wireguard|openvpn|\bVPN\b|\bTAP\b|\btun\d*\b'
        $local = [string]$adapter.NetworkInterfaceType -in @('Ethernet', 'Wireless80211', 'GigabitEthernet', 'FastEthernetFx', 'FastEthernetT') -and
            -not $tunnel -and $adapter.Description -notmatch '(?i)virtual|hyper-v|loopback'
        [pscustomobject]@{
            Id = $adapter.Id; IsUp = $adapter.OperationalStatus -eq [Net.NetworkInformation.OperationalStatus]::Up
            IsLocal = $local; IsTunnel = $tunnel; Ipv4 = $ipv4; Gateways = $gateways
            Mac = $adapter.GetPhysicalAddress().ToString().ToUpperInvariant()
        }
    }
}

function Get-CampusNetworkContext([object[]]$Adapters) {
    try {
        if (-not $PSBoundParameters.ContainsKey('Adapters')) { $Adapters = @(Get-CampusAdapters) }
        $local = @($Adapters | Where-Object { $_.IsUp -and $_.IsLocal })
        $addressed = @($local | Where-Object { @($_.Ipv4).Count -gt 0 })
        $fingerprint = @($Adapters | Sort-Object Id | ForEach-Object {
            $_.Id + ':' + $_.IsUp + ':' + (@($_.Ipv4 | Sort-Object) -join ',') + ':' + (@($_.Gateways | Sort-Object) -join ',')
        }) -join ';'
        return [pscustomobject]@{
            Known = $true; HasLink = $local.Count -gt 0; HasIpv4 = $addressed.Count -gt 0
            HasGateway = @($addressed | Where-Object { @($_.Gateways).Count -gt 0 }).Count -gt 0
            VpnActive = @($Adapters | Where-Object { $_.IsUp -and $_.IsTunnel }).Count -gt 0
            Adapters = @($Adapters); Fingerprint = $fingerprint
        }
    } catch {
        return [pscustomobject]@{ Known = $false; HasLink = $false; HasIpv4 = $false; HasGateway = $false; VpnActive = $false; Adapters = @(); Fingerprint = 'unavailable' }
    }
}

function New-CampusSnapshot([string]$State, [string]$Code, $Network, $Terminal = $null, $Config = $null, [string]$Stage = '', [int]$HttpStatus = 0) {
    $message = ''; $suggestion = ''
    switch ($Code) {
        'Authenticated' { $message = '校园网已登录。'; $suggestion = '保持监测，无需重复登录。' }
        'NotAuthenticated' { $message = '校园网未登录或认证已过期。'; $suggestion = '自动重连程序将立即使用已保存的账号登录；失败重试期间仍按间隔等待。' }
        'AuthenticationUnconfirmed' { $message = '尚未确认校园网认证已失效，已跳过登录。'; $suggestion = '等待下一次认证检查，确认未登录后才会提交账号密码。' }
        'NoLocalLink' { $message = 'Wi-Fi 或有线网络未连接。'; $suggestion = '先连接校园网 Wi-Fi 或网线；连接恢复后会立即复查。' }
        'NoIpv4' { $message = '网卡已连接，但尚未获得可用的 IPv4 地址。'; $suggestion = '等待地址分配；持续异常时检查 DHCP 设置或重新连接校园网。' }
        'LocalInfoUnavailable' { $message = '无法读取本机网卡信息。'; $suggestion = '检查当前进程权限或安全软件限制，再运行检查连接。' }
        'PortalAddressMissing' { $message = '认证接口未提供可用的校园网地址。'; $suggestion = '等待网络地址稳定；持续异常时打开校园网登录页检查。' }
        'LocalAddressChanged' { $message = '认证接口与本机网卡地址不一致。'; $suggestion = '等待网络切换完成，确认当前连接的是校园网，并检查认证地址的 VPN 直连规则。' }
        'RequestTimeout' { $message = '校园网认证接口响应超时。'; $suggestion = '稍后重试；持续超时时检查校园网连接或认证服务器。' }
        'HostUnreachable' { $message = '当前无法路由到校园网认证服务器。'; $suggestion = '检查校园网连接、网关和路由，确认能够访问 10.10.102.50。' }
        'ConnectionRefused' { $message = '认证服务器端口拒绝连接。'; $suggestion = '检查认证服务或防火墙，确认端口 80 和 801 均可访问。' }
        'AccessDenied' { $message = '当前进程访问校园网接口被本机权限或安全策略拒绝。'; $suggestion = '在正常 Windows 用户环境中检查安全软件或进程权限；这不能单独说明 VPN 有问题。' }
        'HttpAccessDenied' { $message = '认证接口拒绝了 HTTP 请求。'; $suggestion = '用浏览器确认登录页是否可访问；持续异常时联系校园网管理员。' }
        'UnexpectedRedirect' { $message = '认证接口返回了非预期跳转。'; $suggestion = '打开校园网登录页确认地址；程序不会跟随跳转提交账号密码。' }
        'ProxyRequired' { $message = '请求被要求进行代理认证。'; $suggestion = '检查 VPN 或网络代理的路由；校园网认证请求应直接访问内网地址。' }
        'ServerError' { $message = '校园网认证服务返回服务器错误。'; $suggestion = '等待服务恢复；持续异常时联系校园网管理员。' }
        'RateLimited' { $message = '校园网认证接口限制了请求频率。'; $suggestion = '等待后再检查或登录，避免反复手动提交。' }
        'EndpointNotFound' { $message = '校园网认证接口地址已不存在。'; $suggestion = '打开网页登录页确认认证协议是否变更，更新工具后再登录。' }
        'ConfigUnavailable' { $message = '校园网服务未能提供认证配置。'; $suggestion = '稍后重试；持续异常时检查网页登录页或联系管理员。' }
        'UnsupportedProtocol' { $message = '校园网认证方式与本工具支持的协议不一致。'; $suggestion = '先使用网页登录；需适配新协议后才能自动重登。' }
        'SessionMismatch' { $message = '在线接口仅返回其他地址的会话，无法确认本机状态。'; $suggestion = '等待网络切换完成或使用网页登录确认，当前不会提交密码。' }
        'InvalidResponse' { $message = '校园网认证接口返回的数据格式异常。'; $suggestion = '检查是否连接正确的校园网；若网页登录正常，可能需要适配接口变化。' }
        'EndpointNotAllowed' { $message = '请求地址不在已配置的校园网接口范围内。'; $suggestion = '检查程序配置，当前不会向该地址发送账号密码。' }
        'HttpError' { $message = '校园网认证接口返回异常 HTTP 状态。'; $suggestion = '稍后重试或检查网页登录页。' }
        default { $message = '校园网认证服务器暂时无法连接。'; $suggestion = '检查校园网连接、认证服务或防火墙；可运行诊断网络查看端口状态。' }
    }
    $vpn = $null -ne $Network -and $Network.VpnActive
    if ($vpn -and $Code -in @('RequestTimeout', 'HostUnreachable', 'ConnectionRefused', 'ConnectionFailed', 'UnexpectedRedirect')) {
        $suggestion += ' 检测到 VPN 隧道已启用，请核对 10.10.102.50/32 的所有端口均直连；仅此现象不能确定是 VPN 拦截。'
    }
    if ($null -ne $Network -and $Network.Known -and $Network.HasIpv4 -and -not $Network.HasGateway -and
        $Code -in @('RequestTimeout', 'HostUnreachable', 'ConnectionFailed')) {
        $suggestion += ' 同时未检测到本地默认网关，可检查 DHCP 或静态路由设置。'
    }
    return [pscustomobject]@{
        State = $State; ReasonCode = $Code; Message = $message; Suggestion = $suggestion
        Stage = $Stage; HttpStatus = $HttpStatus; VpnActive = $vpn; Network = $Network
        Terminal = $Terminal; Config = $Config
    }
}

function Format-CampusDiagnostic($Snapshot) {
    $details = '[' + $Snapshot.ReasonCode
    if ($Snapshot.Stage) { $details += '/' + $Snapshot.Stage }
    if ($Snapshot.HttpStatus -gt 0) { $details += '/HTTP ' + $Snapshot.HttpStatus }
    return ($details + '] ' + $Snapshot.Message + ' ' + $Snapshot.Suggestion)
}

function Test-CampusTcpPort([int]$Port, [int]$TimeoutMilliseconds = 1500) {
    $tcp = New-Object Net.Sockets.TcpClient
    $pending = $null
    try {
        $pending = $tcp.BeginConnect('10.10.102.50', $Port, $null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne($TimeoutMilliseconds)) {
            return [pscustomobject]@{ Port = $Port; Reachable = $false; Code = 'RequestTimeout' }
        }
        $tcp.EndConnect($pending)
        return [pscustomobject]@{ Port = $Port; Reachable = $true; Code = 'Reachable' }
    } catch {
        return [pscustomobject]@{ Port = $Port; Reachable = $false; Code = (Get-CampusFault $_).Code }
    } finally {
        if ($null -ne $pending) { $pending.AsyncWaitHandle.Close() }
        $tcp.Close()
    }
}

function Start-CampusNetworkWatcher {
    $sources = @{}
    $prefix = 'CampusReconnect_' + [guid]::NewGuid().ToString('N')
    foreach ($name in @('NetworkAddressChanged', 'NetworkAvailabilityChanged', 'PowerModeChanged')) {
        try {
            $type = if ($name -eq 'PowerModeChanged') { [Microsoft.Win32.SystemEvents] } else { [Net.NetworkInformation.NetworkChange] }
            $identifier = $prefix + '_' + $name
            Register-ObjectEvent -InputObject $type -EventName $name -SourceIdentifier $identifier -ErrorAction Stop | Out-Null
            $sources[$name] = $identifier
        } catch { } # Polling and adapter fingerprints remain available when events are unsupported.
    }
    return [pscustomobject]@{ Sources = $sources }
}

function Get-CampusWakeReason($Watcher) {
    $reason = ''
    foreach ($name in $Watcher.Sources.Keys) {
        foreach ($queued in @(Get-Event -SourceIdentifier $Watcher.Sources[$name] -ErrorAction SilentlyContinue)) {
            if ($name -eq 'PowerModeChanged') {
                $arguments = @($queued.SourceArgs)
                if ($arguments.Count -gt 0 -and (Get-CampusField $arguments[-1] 'Mode') -eq 'Resume') { $reason = 'Resumed' }
            } elseif ($reason -ne 'Resumed') { $reason = 'NetworkChanged' }
            Remove-Event -EventIdentifier $queued.EventIdentifier -ErrorAction SilentlyContinue
        }
    }
    return $reason
}

function Stop-CampusNetworkWatcher($Watcher) {
    if ($null -eq $Watcher) { return }
    foreach ($identifier in $Watcher.Sources.Values) {
        Unregister-Event -SourceIdentifier $identifier -ErrorAction SilentlyContinue
        foreach ($queued in @(Get-Event -SourceIdentifier $identifier -ErrorAction SilentlyContinue)) {
            Remove-Event -EventIdentifier $queued.EventIdentifier -ErrorAction SilentlyContinue
        }
    }
}

function Wait-CampusNextCheck($Stop, $Watcher, [string]$Fingerprint, [int]$DelayMilliseconds = 5000, $CheckSignal = $null) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $lastTick = [datetime]::UtcNow
    $lastAdapterCheck = 0
    while ($true) {
        if ($Stop.WaitOne(0)) { return 'Stop' }
        if ($null -ne $CheckSignal -and $CheckSignal.WaitOne(0)) { return 'ManualCheck' }
        $reason = Get-CampusWakeReason $Watcher
        if ($reason) { return $reason }
        $now = [datetime]::UtcNow
        if (($now - $lastTick).TotalSeconds -gt 10) { return 'Resumed' }
        $lastTick = $now
        if ($timer.ElapsedMilliseconds -ge $DelayMilliseconds) { return 'Poll' }
        if ($timer.ElapsedMilliseconds - $lastAdapterCheck -ge 1000) {
            $lastAdapterCheck = $timer.ElapsedMilliseconds
            if ((Get-CampusNetworkContext).Fingerprint -ne $Fingerprint) { return 'NetworkChanged' }
        }
        if ($Stop.WaitOne([Math]::Max(1, [Math]::Min(250, $DelayMilliseconds - [int]$timer.ElapsedMilliseconds)))) { return 'Stop' }
    }
}
