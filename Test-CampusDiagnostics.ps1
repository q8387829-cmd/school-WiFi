$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CampusNetwork.Core.ps1')
Add-Type -AssemblyName System.Net.Http
$script:checks = 0
function Assert-Diagnostic([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw ('FAIL: ' + $Name) }
    $script:checks++
    Write-Host ('PASS: ' + $Name)
}
function New-DiagnosticClient([object[]]$Steps) {
    $client = [pscustomobject]@{ Steps = (New-Object 'Collections.Generic.Queue[object]'); Requests = (New-Object 'Collections.Generic.List[string]') }
    foreach ($step in $Steps) { $client.Steps.Enqueue($step) }
    $client | Add-Member ScriptMethod GetAsync {
        param($Uri)
        $this.Requests.Add($Uri)
        if ($this.Steps.Count -eq 0) { throw 'Unexpected HTTP request' }
        $step = $this.Steps.Dequeue()
        if ($step -is [Exception]) { throw $step }
        $status = if ($step -is [string]) { 200 } else { $step.Status }
        $body = if ($step -is [string]) { $step } else { $step.Body }
        $response = New-Object Net.Http.HttpResponseMessage([Enum]::ToObject([Net.HttpStatusCode], [int]$status))
        $response.Content = New-Object Net.Http.StringContent($body, [Text.Encoding]::UTF8)
        $awaitable = [pscustomobject]@{ Response = $response }
        $awaitable | Add-Member ScriptMethod GetAwaiter { return $this }
        $awaitable | Add-Member ScriptMethod GetResult { return $this.Response }
        return $awaitable
    }
    return $client
}
$wifi = [pscustomobject]@{ Id = 'wifi'; IsUp = $true; IsLocal = $true; IsTunnel = $false; Ipv4 = @('10.9.8.7'); Gateways = @('10.9.8.1'); Mac = 'AABBCCDDEEFF' }
$tunnel = [pscustomobject]@{ Id = 'vpn'; IsUp = $true; IsLocal = $false; IsTunnel = $true; Ipv4 = @('172.19.0.1'); Gateways = @('172.19.0.2'); Mac = '' }
$network = Get-CampusNetworkContext -Adapters @($wifi)
$vpnNetwork = Get-CampusNetworkContext -Adapters @($wifi, $tunnel)
Assert-Diagnostic ($network.Known -and $network.HasLink -and $network.HasIpv4 -and $network.HasGateway -and -not $network.VpnActive) 'Connected Wi-Fi is recognized independently from VPN'
Assert-Diagnostic ($vpnNetwork.VpnActive -and $vpnNetwork.HasLink) 'Active VPN and local network can coexist'
Assert-Diagnostic ($vpnNetwork.Fingerprint -eq (Get-CampusNetworkContext -Adapters @($tunnel, $wifi)).Fingerprint) 'Adapter enumeration order does not cause false network changes'
$changedWifi = [pscustomobject]@{ Id = 'wifi'; IsUp = $true; IsLocal = $true; IsTunnel = $false; Ipv4 = @('10.9.8.8'); Gateways = @('10.9.8.1'); Mac = 'AABBCCDDEEFF' }
$changedNetwork = Get-CampusNetworkContext -Adapters @($changedWifi)
Assert-Diagnostic ($network.Fingerprint -ne $changedNetwork.Fingerprint) 'DHCP address change changes the network fingerprint'
$onlyVpn = Get-CampusNetworkContext -Adapters @($tunnel)
$client = New-DiagnosticClient @()
$snapshot = Get-CampusSnapshot $client $onlyVpn
Assert-Diagnostic ($snapshot.ReasonCode -eq 'NoLocalLink' -and $snapshot.State -eq 'Unknown' -and $client.Requests.Count -eq 0) 'VPN alone cannot replace disconnected Wi-Fi or trigger password submission'
$unaddressed = [pscustomobject]@{ Id = 'wifi'; IsUp = $true; IsLocal = $true; IsTunnel = $false; Ipv4 = @(); Gateways = @(); Mac = 'AABBCCDDEEFF' }
$client = New-DiagnosticClient @()
Assert-Diagnostic ((Get-CampusSnapshot $client (Get-CampusNetworkContext -Adapters @($unaddressed))).ReasonCode -eq 'NoIpv4' -and $client.Requests.Count -eq 0) 'Missing DHCP address is distinguished before contacting the portal'
$unavailable = [pscustomobject]@{ Known = $false; HasLink = $false; HasIpv4 = $false; HasGateway = $false; VpnActive = $false; Adapters = @(); Fingerprint = 'unavailable' }
$client = New-DiagnosticClient @()
Assert-Diagnostic ((Get-CampusSnapshot $client $unavailable).ReasonCode -eq 'LocalInfoUnavailable' -and $client.Requests.Count -eq 0) 'Unavailable network metadata is reported without assuming authentication expiry'

$kernel = 'campusCallback({"result":1,"v4ip":"10.9.8.7"})'
$config = 'campusCallback({"code":1,"data":{"login_method":1,"check_online_method":1}})'
$online = 'campusCallback({"result":1,"list":[{"online_ip":"10.9.8.7"}]})'
$offline = 'campusCallback({"result":1,"list":[],"total":0})'
$client = New-DiagnosticClient @($kernel, $config, $online)
Assert-Diagnostic ((Get-CampusSnapshot $client $vpnNetwork).ReasonCode -eq 'Authenticated') 'VPN presence does not override confirmed authentication'
$client = New-DiagnosticClient @($kernel, $config, $offline)
$snapshot = Get-CampusSnapshot $client $vpnNetwork
Assert-Diagnostic ($snapshot.State -eq 'Offline' -and $snapshot.ReasonCode -eq 'NotAuthenticated' -and (Get-CampusAction (New-CampusMonitorState) $snapshot.State ([datetime]::UtcNow)) -eq 'Login') 'Confirmed expiry still triggers immediate login while VPN is active'
$client = New-DiagnosticClient @('campusCallback({"result":0})')
Assert-Diagnostic ((Get-CampusSnapshot $client $network).ReasonCode -eq 'PortalAddressMissing') 'Missing portal-side device address has a specific diagnosis'
$client = New-DiagnosticClient @('campusCallback({"result":1,"v4ip":"10.8.8.8"})')
Assert-Diagnostic ((Get-CampusSnapshot $client $network).ReasonCode -eq 'LocalAddressChanged' -and $client.Requests.Count -eq 1) 'Stale device address prevents subsequent authentication requests'
$client = New-DiagnosticClient @($kernel, 'campusCallback({"code":0})')
Assert-Diagnostic ((Get-CampusSnapshot $client $network).ReasonCode -eq 'ConfigUnavailable') 'Configuration service failure is distinguished from an expired login'
$client = New-DiagnosticClient @($kernel, 'campusCallback({"code":1,"data":{"login_method":99}})')
Assert-Diagnostic ((Get-CampusSnapshot $client $network).ReasonCode -eq 'UnsupportedProtocol' -and $client.Requests.Count -eq 2) 'Protocol changes prevent unsupported credential submission'
$client = New-DiagnosticClient @($kernel, $config, 'campusCallback({"result":1,"list":[{"online_ip":"10.8.8.8"}]})')
Assert-Diagnostic ((Get-CampusSnapshot $client $network).ReasonCode -eq 'SessionMismatch') 'Other-device session is diagnosed separately'
$client = New-DiagnosticClient @($kernel, $config, 'campusCallback({"result":0,"msg":"服务器异常 fake-secret"})')
$snapshot = Get-CampusSnapshot $client $network
Assert-Diagnostic ($snapshot.State -eq 'Unknown' -and $snapshot.ReasonCode -eq 'ServerError' -and (Format-CampusDiagnostic $snapshot) -notmatch 'fake-secret') 'Explicit service failure is never treated as an expired account or echoed to logs'

foreach ($case in @(
    @{ Status = 302; Code = 'UnexpectedRedirect' }, @{ Status = 403; Code = 'HttpAccessDenied' },
    @{ Status = 404; Code = 'EndpointNotFound' }, @{ Status = 407; Code = 'ProxyRequired' },
    @{ Status = 429; Code = 'RateLimited' }, @{ Status = 503; Code = 'ServerError' }
)) {
    $client = New-DiagnosticClient @([pscustomobject]@{ Status = $case.Status; Body = 'http://example.invalid/?user_password=fake-secret' })
    $snapshot = Get-CampusSnapshot $client $vpnNetwork
    Assert-Diagnostic ($snapshot.ReasonCode -eq $case.Code -and $snapshot.HttpStatus -eq $case.Status -and $snapshot.Stage -eq 'KernelStatus' -and $snapshot.State -eq 'Unknown') ('HTTP ' + $case.Status + ' retains a safe reason and failing stage')
    Assert-Diagnostic ((Format-CampusDiagnostic $snapshot) -notmatch 'fake-secret|example.invalid') ('HTTP ' + $case.Status + ' does not expose response bodies or request URLs')
}
foreach ($stage in @('PortalConfig', 'SessionList')) {
    [object[]]$steps = if ($stage -eq 'PortalConfig') { @($kernel) } else { @($kernel, $config) }
    $client = New-DiagnosticClient @($steps + [pscustomobject]@{ Status = 503; Body = '' })
    $snapshot = Get-CampusSnapshot $client $vpnNetwork
    Assert-Diagnostic ($snapshot.ReasonCode -eq 'ServerError' -and $snapshot.Stage -eq $stage -and $snapshot.Suggestion -notmatch '检测到 VPN') ($stage + ' failure is localized without blaming VPN')
}
foreach ($case in @(
    @{ Exception = (New-Object Threading.Tasks.TaskCanceledException('fake-secret')); Code = 'RequestTimeout' },
    @{ Exception = (New-Object Net.Sockets.SocketException(10013)); Code = 'AccessDenied' },
    @{ Exception = (New-Object Net.Sockets.SocketException(10061)); Code = 'ConnectionRefused' },
    @{ Exception = (New-Object Net.Sockets.SocketException(10065)); Code = 'HostUnreachable' }
)) {
    $client = New-DiagnosticClient @($case.Exception)
    $snapshot = Get-CampusSnapshot $client $vpnNetwork
    Assert-Diagnostic ($snapshot.ReasonCode -eq $case.Code -and $snapshot.State -eq 'Unknown' -and $snapshot.Stage -eq 'KernelStatus') ($case.Code + ' is diagnosed from exception types instead of raw error text')
    Assert-Diagnostic ((Get-CampusAction (New-CampusMonitorState) $snapshot.State ([datetime]::UtcNow)) -eq 'Wait') ($case.Code + ' never triggers blind login')
    if ($case.Code -eq 'RequestTimeout') {
        Assert-Diagnostic ($snapshot.Suggestion -match '10.10.102.50/32' -and $snapshot.Suggestion -match '不能确定' -and (Format-CampusDiagnostic $snapshot) -notmatch 'fake-secret') 'VPN-related routing is presented as a possibility without leaking exceptions'
    }
}
$client = New-DiagnosticClient @('<html>fake-secret login required</html>')
Assert-Diagnostic ((Get-CampusSnapshot $client $network).ReasonCode -eq 'InvalidResponse') 'Unexpected HTML is diagnosed as a protocol response problem'
$noGatewayWifi = [pscustomobject]@{ Id = 'wifi'; IsUp = $true; IsLocal = $true; IsTunnel = $false; Ipv4 = @('10.9.8.7'); Gateways = @(); Mac = 'AABBCCDDEEFF' }
$noGateway = Get-CampusNetworkContext -Adapters @($noGatewayWifi)
$client = New-DiagnosticClient @($kernel, $config, $online)
Assert-Diagnostic ((Get-CampusSnapshot $client $noGateway).State -eq 'Online') 'A missing default gateway does not invalidate a working static route'
$client = New-DiagnosticClient @((New-Object Threading.Tasks.TaskCanceledException))
Assert-Diagnostic ((Get-CampusSnapshot $client $noGateway).Suggestion -match '默认网关') 'Missing gateway is surfaced as additional evidence after a connection failure'

$sources = @{ NetworkAddressChanged = 'CampusTest_Address_' + [guid]::NewGuid().ToString('N'); PowerModeChanged = 'CampusTest_Power_' + [guid]::NewGuid().ToString('N') }
$watcher = [pscustomobject]@{ Sources = $sources }
$stop = New-Object Threading.ManualResetEvent($false)
try {
    New-Event -SourceIdentifier $sources.PowerModeChanged -EventArguments @((New-Object Microsoft.Win32.PowerModeChangedEventArgs([Microsoft.Win32.PowerModes]::Resume))) | Out-Null
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $reason = Wait-CampusNextCheck $stop $watcher $network.Fingerprint
    Assert-Diagnostic ($reason -eq 'Resumed' -and $timer.ElapsedMilliseconds -lt 1000) 'Resume notification bypasses the five-second polling wait'
    New-Event -SourceIdentifier $sources.NetworkAddressChanged | Out-Null
    Assert-Diagnostic ((Wait-CampusNextCheck $stop $watcher $network.Fingerprint) -eq 'NetworkChanged') 'Network-change notification immediately requests a fresh check'
    Assert-Diagnostic ((Get-CampusWakeReason $watcher) -eq '') 'Handled notifications are drained instead of triggering repeated logins'
    New-Event -SourceIdentifier $sources.PowerModeChanged -EventArguments @((New-Object Microsoft.Win32.PowerModeChangedEventArgs([Microsoft.Win32.PowerModes]::Suspend))) | Out-Null
    Assert-Diagnostic ((Get-CampusWakeReason $watcher) -eq '') 'Suspend notification is not misreported as resume'
    Assert-Diagnostic ((Wait-CampusNextCheck $stop $watcher $network.Fingerprint 25) -eq 'Poll') 'Normal polling remains available without events'
    [void]$stop.Set()
    Assert-Diagnostic ((Wait-CampusNextCheck $stop $watcher $network.Fingerprint) -eq 'Stop') 'Stop request interrupts the polling wait'
    [void]$stop.Reset()
    $originalProvider = (Get-Item Function:\Get-CampusNetworkContext).ScriptBlock
    function Get-CampusNetworkContext { return $changedNetwork }
    try {
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $reason = Wait-CampusNextCheck $stop $watcher $network.Fingerprint
        Assert-Diagnostic ($reason -eq 'NetworkChanged' -and $timer.ElapsedMilliseconds -lt 3000) 'Adapter fingerprint detects changes when no system notification arrives'
    } finally { Set-Item Function:\Get-CampusNetworkContext -Value $originalProvider }
} finally {
    Stop-CampusNetworkWatcher $watcher
    $stop.Dispose()
}
$liveWatcher = Start-CampusNetworkWatcher
try {
    Assert-Diagnostic ($liveWatcher.Sources.ContainsKey('NetworkAddressChanged') -and $liveWatcher.Sources.ContainsKey('NetworkAvailabilityChanged')) 'Windows network-change subscriptions can be registered without network changes'
    $identifiers = @($liveWatcher.Sources.Values)
} finally { Stop-CampusNetworkWatcher $liveWatcher }
Assert-Diagnostic (@(Get-EventSubscriber | Where-Object { $_.SourceIdentifier -in $identifiers }).Count -eq 0) 'Watcher cleanup releases subscriptions'
Write-Host ('All ' + $script:checks + ' diagnostic checks passed. No real credentials or network settings changed.')
