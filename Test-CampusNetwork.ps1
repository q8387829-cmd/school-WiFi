$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CampusNetwork.Core.ps1')
Add-Type -AssemblyName System.Net.Http
$script:testCount = 0

function Assert-Campus([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw ('FAIL: ' + $Name) }
    $script:testCount++
    Write-Host ('PASS: ' + $Name)
}

function New-MockCampusClient([string[]]$Replies, [Net.HttpStatusCode]$StatusCode = [Net.HttpStatusCode]::OK) {
    $mock = [pscustomobject]@{ Replies = (New-Object 'Collections.Generic.Queue[string]'); Requests = (New-Object 'Collections.Generic.List[string]'); StatusCode = $StatusCode }
    foreach ($reply in $Replies) { $mock.Replies.Enqueue($reply) }
    $mock | Add-Member ScriptMethod GetAsync {
        param($Uri)
        $this.Requests.Add($Uri)
        if ($this.Replies.Count -eq 0) { throw 'Simulated network failure' }
        $response = New-Object Net.Http.HttpResponseMessage($this.StatusCode)
        $response.Content = New-Object Net.Http.StringContent($this.Replies.Dequeue(), [Text.Encoding]::UTF8)
        $awaitable = [pscustomobject]@{ Response = $response }
        $awaitable | Add-Member ScriptMethod GetAwaiter { return $this }
        $awaitable | Add-Member ScriptMethod GetResult { return $this.Response }
        return $awaitable
    }
    return $mock
}

$parsed = ConvertFrom-CampusJsonp ' campusCallback({"result":1,"msg":"正常"}); '
Assert-Campus ($parsed.result -eq 1 -and $parsed.msg -eq '正常') 'Parse JSONP as data with UTF-8 text'
$rejected = $false
try { ConvertFrom-CampusJsonp 'campusCallback({"result":1});alert(1)' | Out-Null } catch { $rejected = $true }
Assert-Campus $rejected 'Reject executable JavaScript after callback'
$rejected = $false
try { ConvertFrom-CampusJsonp 'otherCallback({"result":1})' | Out-Null } catch { $rejected = $true }
Assert-Campus $rejected 'Reject unexpected callback'
$encoded = ConvertTo-CampusQuery @{ password = 'fake &+=?#中文' }
Assert-Campus ([uri]::UnescapeDataString(($encoded -split '=', 2)[1]) -eq 'fake &+=?#中文') 'Encode special characters without changing password'
Assert-Campus ((ConvertTo-CampusIpNumber '10.59.2.212') -eq 171639508) 'Match browser IPv4 integer encoding'

$now = [datetime]::UtcNow
$state = New-CampusMonitorState
Assert-Campus ((Get-CampusAction $state 'Offline' $now) -eq 'Login') 'First offline observation immediately triggers login'
Assert-Campus ((Get-CampusAction $state 'Unknown' $now) -eq 'Wait') 'Unknown status does not trigger credential submission'
Assert-Campus ((Get-CampusAction $state 'Offline' $now) -eq 'Login') 'First offline observation after network recovery immediately triggers login'
Assert-Campus ((Get-CampusAction $state 'Online' $now) -eq 'Wait') 'Online state prevents duplicate login'
Assert-Campus ((Set-CampusFailure $state $now) -eq 60) 'First failed login waits 60 seconds'
[void](Get-CampusAction $state 'Offline' $now)
Assert-Campus ((Get-CampusAction $state 'Offline' $now.AddSeconds(59)) -eq 'Wait') 'Retry cooldown prevents excessive submissions'
Assert-Campus ((Get-CampusAction $state 'Offline' $now.AddSeconds(60)) -eq 'Login') 'Retry allowed after cooldown'
Assert-Campus ((Set-CampusFailure $state $now) -eq 120) 'Second failed login waits 120 seconds'
Assert-Campus ((Set-CampusFailure $state $now) -eq 900) 'Third failed login waits 15 minutes'
[void](Get-CampusAction $state 'Online' $now)
Assert-Campus ($state.Failures -eq 0 -and $state.NextAttempt -eq [datetime]::MinValue) 'Successful authentication clears failure backoff'

$realClient = New-CampusHttpClient
try { Assert-Campus ($realClient.Timeout.TotalSeconds -eq 10) 'HTTP timeout is bounded' } finally { $realClient.Dispose() }
$mock = New-MockCampusClient @('campusCallback({"result":1})')
$rejected = $false
try { Invoke-CampusJsonp $mock 'http://example.com/login' @{} | Out-Null } catch { $rejected = $true }
Assert-Campus ($rejected -and $mock.Requests.Count -eq 0) 'Credentials cannot be sent to an unapproved endpoint'
$mock = New-MockCampusClient @('') ([Net.HttpStatusCode]::Found)
$rejected = $false
try { Invoke-CampusJsonp $mock 'http://10.10.102.50:801/eportal/portal/login' @{ user_password = 'fake' } | Out-Null } catch { $rejected = $true }
Assert-Campus ($rejected -and $mock.Requests.Count -eq 1) 'Redirect response is rejected without a second request'

$credential = New-Object Management.Automation.PSCredential('testuser@unicom', (ConvertTo-SecureString 'fake &+=?#中文' -AsPlainText -Force))
$loginAdapter = [pscustomobject]@{
    Id = 'test-wifi'; IsUp = $true; IsLocal = $true; IsTunnel = $false
    Ipv4 = @('10.9.8.7'); Gateways = @('10.9.8.1'); Mac = 'AABBCCDDEEFF'
}
$loginNetwork = Get-CampusNetworkContext -Adapters @($loginAdapter)
$snapshot = [pscustomobject]@{
    State = 'Offline'; Network = $loginNetwork
    Config = [pscustomobject]@{ login_method = 1; en_md5 = 0; password_cut = 0; account_prefix = 0 }
    Terminal = [pscustomobject]@{ Ip = '10.9.8.7'; Mac = 'AABBCCDDEEFF'; Ipv6 = '' }
}
$mock = New-MockCampusClient @('campusCallback({"result":1})')
$login = Invoke-CampusLogin $mock $snapshot $credential -Network $loginNetwork
Assert-Campus ($login.Accepted -and -not $login.Stop) 'Recognize login response without claiming Internet recovery'
$requestUri = [uri]$mock.Requests[0]
$parameters = @{}
foreach ($part in $requestUri.Query.TrimStart('?').Split('&')) {
    $pair = $part.Split('=', 2)
    $parameters[[uri]::UnescapeDataString($pair[0])] = [uri]::UnescapeDataString($pair[1])
}
Assert-Campus ($requestUri.Host -eq '10.10.102.50' -and $requestUri.Port -eq 801 -and $requestUri.AbsolutePath -eq '/eportal/portal/login') 'Login uses observed portal endpoint'
Assert-Campus ($parameters.user_account -eq 'testuser@unicom' -and $parameters.user_password -eq 'fake &+=?#中文' -and $parameters.wlan_user_ip -eq '10.9.8.7') 'Login preserves credentials and current device IP'
$mock = New-MockCampusClient @('campusCallback({"result":0,"ret_code":1,"msg":"密码错误 fake &+=?#中文"})')
$login = Invoke-CampusLogin $mock $snapshot $credential -Network $loginNetwork
Assert-Campus ($login.Stop -and -not $login.Accepted -and $login.Reason -notmatch 'fake') 'Wrong password stops automatic submissions and omits raw server response'
$mock = New-MockCampusClient @()
$login = Invoke-CampusLogin $mock $snapshot $credential -Network $loginNetwork
Assert-Campus (-not $login.Accepted -and -not $login.Stop -and $login.Reason -notmatch 'fake') 'Network errors are recoverable and do not expose request URLs'
$snapshot.Config.login_method = 99
$mock = New-MockCampusClient @()
$login = Invoke-CampusLogin $mock $snapshot $credential -Network $loginNetwork
Assert-Campus ($login.Stop -and $mock.Requests.Count -eq 0) 'Unknown authentication protocol causes no credential submission'

$snapshot.Config.login_method = 1
foreach ($authState in @('Unknown', 'Online', '')) {
    $snapshot.State = $authState
    $mock = New-MockCampusClient @('campusCallback({"result":1})')
    $login = Invoke-CampusLogin $mock $snapshot $credential -Network $loginNetwork
    Assert-Campus (-not $login.Accepted -and -not $login.Stop -and $mock.Requests.Count -eq 0) ('Login entry point refuses an unconfirmed offline state: ' + $authState)
}
$snapshot.State = 'Offline'
foreach ($change in @('Address', 'Mac', 'Disconnected', 'NoIpv4', 'Unavailable')) {
    $adapter = $loginAdapter.PSObject.Copy()
    switch ($change) {
        'Address' { $adapter.Ipv4 = @('10.9.8.8') }
        'Mac' { $adapter.Mac = '112233445566' }
        'Disconnected' { $adapter.IsUp = $false }
        'NoIpv4' { $adapter.Ipv4 = @() }
    }
    $changedNetwork = Get-CampusNetworkContext -Adapters @($adapter)
    if ($change -eq 'Unavailable') { $changedNetwork.Known = $false }
    $mock = New-MockCampusClient @('campusCallback({"result":1})')
    $login = Invoke-CampusLogin $mock $snapshot $credential -Network $changedNetwork
    Assert-Campus (-not $login.Accepted -and -not $login.Stop -and $mock.Requests.Count -eq 0 -and $login.Reason -notmatch 'fake|testuser') ('Network change before login prevents credential submission: ' + $change)
}
$vpnAdapter = [pscustomobject]@{ Id = 'vpn'; IsUp = $true; IsLocal = $false; IsTunnel = $true; Ipv4 = @('172.19.0.1'); Gateways = @(); Mac = '' }
$mock = New-MockCampusClient @('campusCallback({"result":1})')
$login = Invoke-CampusLogin $mock $snapshot $credential -Network (Get-CampusNetworkContext -Adapters @($loginAdapter, $vpnAdapter))
Assert-Campus ($login.Accepted -and $mock.Requests.Count -eq 1) 'A VPN change with the same local terminal still permits immediate login'

# Mock network-interface discovery only for deterministic offline response tests.
function Get-CampusTerminal($CoreStatus) { return [pscustomobject]@{ Ip = '10.9.8.7'; Mac = 'AABBCCDDEEFF'; Ipv6 = '' } }
$coreResponse = 'campusCallback({"result":1,"v4ip":"10.9.8.7"})'
$configResponse = 'campusCallback({"code":1,"data":{"login_method":1,"check_online_method":1}})'
$mockNetwork = Get-CampusNetworkContext -Adapters @([pscustomobject]@{
    Id = 'test-wifi'; IsUp = $true; IsLocal = $true; IsTunnel = $false
    Ipv4 = @('10.9.8.7'); Gateways = @('10.9.8.1'); Mac = 'AABBCCDDEEFF'
})
$mock = New-MockCampusClient @($coreResponse, $configResponse, 'campusCallback({"result":1,"list":[],"total":0})')
Assert-Campus ((Get-CampusSnapshot $mock $mockNetwork).State -eq 'Offline') 'RADIUS offline status overrides stale core online state'
$mock = New-MockCampusClient @($coreResponse, $configResponse, 'campusCallback({"result":1,"list":[{"online_ip":"10.9.8.7"}],"total":1})')
Assert-Campus ((Get-CampusSnapshot $mock $mockNetwork).State -eq 'Online') 'Recognize this device in online session list'
$mock = New-MockCampusClient @($coreResponse, $configResponse, 'campusCallback({"result":1,"list":[{"online_ip":"10.8.8.8"}],"total":1})')
Assert-Campus ((Get-CampusSnapshot $mock $mockNetwork).State -eq 'Unknown') 'Another device session does not justify login submission'
$mock = New-MockCampusClient @($coreResponse, $configResponse, 'campusCallback({"result":1})')
Assert-Campus ((Get-CampusSnapshot $mock $mockNetwork).State -eq 'Unknown') 'Missing session list is not treated as an expired session'
foreach ($listValue in @('null', '""', '{}', '0')) {
    $mock = New-MockCampusClient @($coreResponse, $configResponse, ('campusCallback({"result":1,"list":' + $listValue + '})'))
    $invalid = Get-CampusSnapshot $mock $mockNetwork
    Assert-Campus ($invalid.State -eq 'Unknown' -and $invalid.ReasonCode -eq 'InvalidResponse') ('Malformed session collection cannot cause login: ' + $listValue)
}
$mock = New-MockCampusClient @($coreResponse, $configResponse, 'campusCallback({"result":0,"list":[{"online_ip":"10.9.8.7"}]})')
Assert-Campus ((Get-CampusSnapshot $mock $mockNetwork).State -eq 'Unknown') 'Contradictory offline and online-session responses cannot cause login'
foreach ($methodField in @('', ',"check_online_method":99', ',"check_online_method":null')) {
    $mock = New-MockCampusClient @($coreResponse, ('campusCallback({"code":1,"data":{"login_method":1' + $methodField + '}})'))
    $invalid = Get-CampusSnapshot $mock $mockNetwork
    Assert-Campus ($invalid.State -eq 'Unknown' -and $invalid.ReasonCode -eq 'UnsupportedProtocol') ('Missing or unsupported status protocol cannot fall back to stale kernel status: ' + $methodField)
}
$mock = New-MockCampusClient @($coreResponse, 'campusCallback({"code":1,"data":{"login_method":1,"check_online_method":0}})')
Assert-Campus ((Get-CampusSnapshot $mock $mockNetwork).State -eq 'Online') 'Explicitly configured kernel status remains supported'
$mock = New-MockCampusClient @()
Assert-Campus ((Get-CampusSnapshot $mock $mockNetwork).State -eq 'Unknown') 'Unreachable portal is not treated as an expired session'

$temporaryCredential = Join-Path $PSScriptRoot '.test-credential.xml'
try {
    Save-CampusCredential $temporaryCredential $credential
    $stored = Get-Content -LiteralPath $temporaryCredential -Raw
    $restored = Read-CampusCredential $temporaryCredential
    Assert-Campus ($stored -notmatch 'fake' -and $restored.GetNetworkCredential().Password -eq 'fake &+=?#中文') 'Windows DPAPI encrypts saved password and decrypts for same user'
    $replacement = New-Object Management.Automation.PSCredential('newtest@cmcc', (ConvertTo-SecureString 'new fake password' -AsPlainText -Force))
    Save-CampusCredential $temporaryCredential $replacement
    $latest = Read-CampusCredential $temporaryCredential
    Assert-Campus ($latest.UserName -eq 'newtest@cmcc' -and $latest.GetNetworkCredential().Password -eq 'new fake password') 'Existing credential record can be updated and reloaded'
    Assert-Campus (@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '.test-credential.xml.*.tmp').Count -eq 0) 'Saving credentials leaves no temporary record behind'
    [IO.File]::WriteAllText($temporaryCredential, 'invalid credential data')
    $rejected = $false
    try { Read-CampusCredential $temporaryCredential | Out-Null } catch { $rejected = $true }
    Assert-Campus $rejected 'Corrupted credential records are rejected'
    $emptyAccount = New-Object Management.Automation.PSCredential(' ', (ConvertTo-SecureString 'fake' -AsPlainText -Force))
    $rejected = $false
    try { Save-CampusCredential $temporaryCredential $emptyAccount } catch { $rejected = $true }
    Assert-Campus $rejected 'Blank saved account is rejected'
} finally { if (Test-Path -LiteralPath $temporaryCredential) { Remove-Item -LiteralPath $temporaryCredential -Force } }
$rejected = $false
try { Read-CampusCredential $temporaryCredential | Out-Null } catch { $rejected = $true }
Assert-Campus $rejected 'Missing credential record gives a configuration error'
Write-Host ('All ' + $script:testCount + ' checks passed. No real credentials submitted.')
