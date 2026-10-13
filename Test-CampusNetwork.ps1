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
Assert-Campus ((Get-CampusAction $state 'Offline' $now) -eq 'Wait') 'One offline observation does not trigger login'
Assert-Campus ((Get-CampusAction $state 'Offline' $now) -eq 'Login') 'Two consecutive offline observations trigger login'
Assert-Campus ((Get-CampusAction $state 'Unknown' $now) -eq 'Wait' -and $state.OfflineCount -eq 0) 'Unknown state resets offline confirmation'
[void](Get-CampusAction $state 'Offline' $now)
Assert-Campus ((Get-CampusAction $state 'Online' $now) -eq 'Wait' -and $state.OfflineCount -eq 0) 'Online state prevents duplicate login'
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
$snapshot = [pscustomobject]@{
    Config = [pscustomobject]@{ login_method = 1; en_md5 = 0; password_cut = 0; account_prefix = 0 }
    Terminal = [pscustomobject]@{ Ip = '10.9.8.7'; Mac = 'AABBCCDDEEFF'; Ipv6 = '' }
}
$mock = New-MockCampusClient @('campusCallback({"result":1})')
$login = Invoke-CampusLogin $mock $snapshot $credential
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
$login = Invoke-CampusLogin $mock $snapshot $credential
Assert-Campus ($login.Stop -and -not $login.Accepted -and $login.Reason -notmatch 'fake') 'Wrong password stops automatic submissions and omits raw server response'
$mock = New-MockCampusClient @()
$login = Invoke-CampusLogin $mock $snapshot $credential
Assert-Campus (-not $login.Accepted -and -not $login.Stop -and $login.Reason -notmatch 'fake') 'Network errors are recoverable and do not expose request URLs'
$snapshot.Config.login_method = 99
$mock = New-MockCampusClient @()
$login = Invoke-CampusLogin $mock $snapshot $credential
Assert-Campus ($login.Stop -and $mock.Requests.Count -eq 0) 'Unknown authentication protocol causes no credential submission'

# Mock network-interface discovery only for deterministic offline response tests.
function Get-CampusTerminal($CoreStatus) { return [pscustomobject]@{ Ip = '10.9.8.7'; Mac = 'AABBCCDDEEFF'; Ipv6 = '' } }
$coreResponse = 'campusCallback({"result":1,"v4ip":"10.9.8.7"})'
$configResponse = 'campusCallback({"code":1,"data":{"login_method":1,"check_online_method":1}})'
$mock = New-MockCampusClient @($coreResponse, $configResponse, 'campusCallback({"result":1,"list":[],"total":0})')
Assert-Campus ((Get-CampusSnapshot $mock).State -eq 'Offline') 'RADIUS offline status overrides stale core online state'
$mock = New-MockCampusClient @($coreResponse, $configResponse, 'campusCallback({"result":1,"list":[{"online_ip":"10.9.8.7"}],"total":1})')
Assert-Campus ((Get-CampusSnapshot $mock).State -eq 'Online') 'Recognize this device in online session list'
$mock = New-MockCampusClient @($coreResponse, $configResponse, 'campusCallback({"result":1,"list":[{"online_ip":"10.8.8.8"}],"total":1})')
Assert-Campus ((Get-CampusSnapshot $mock).State -eq 'Unknown') 'Another device session does not justify login submission'
$mock = New-MockCampusClient @($coreResponse, $configResponse, 'campusCallback({"result":1})')
Assert-Campus ((Get-CampusSnapshot $mock).State -eq 'Unknown') 'Missing session list is not treated as an expired session'
$mock = New-MockCampusClient @()
Assert-Campus ((Get-CampusSnapshot $mock).State -eq 'Unknown') 'Unreachable portal is not treated as an expired session'

$temporaryCredential = Join-Path $PSScriptRoot '.test-credential.xml'
try {
    $credential | Export-Clixml -LiteralPath $temporaryCredential -Encoding UTF8
    $stored = Get-Content -LiteralPath $temporaryCredential -Raw
    $restored = Import-Clixml -LiteralPath $temporaryCredential
    Assert-Campus ($stored -notmatch 'fake' -and $restored.GetNetworkCredential().Password -eq 'fake &+=?#中文') 'Windows DPAPI encrypts saved password and decrypts for same user'
} finally { if (Test-Path -LiteralPath $temporaryCredential) { Remove-Item -LiteralPath $temporaryCredential -Force } }
Write-Host ('All ' + $script:testCount + ' checks passed. No real credentials submitted.')
