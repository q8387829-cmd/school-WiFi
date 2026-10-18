$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CampusNetwork.Service.ps1')
$script:serviceChecks = 0

function Assert-Service([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw ('FAIL: ' + $Name) }
    $script:serviceChecks++
    Write-Host ('PASS: ' + $Name)
}

function Assert-ServiceThrows([scriptblock]$Action, [string]$Name, [string]$Forbidden = '') {
    $caught = $false
    $safe = $true
    try { & $Action | Out-Null } catch {
        $caught = $true
        if ($Forbidden) { $safe = $_.Exception.Message -notmatch $Forbidden }
    }
    Assert-Service ($caught -and $safe) $Name
}

# Every write is confined to a newly created directory beneath the ignored publish folder.
# These tests never import the user's real data/credential.xml or contact the campus portal.
$publishRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.publish'))
$testRoot = [IO.Path]::GetFullPath((Join-Path $publishRoot ('test-service-' + [guid]::NewGuid().ToString('N'))))
if (-not $testRoot.StartsWith(($publishRoot.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Unsafe service-test directory.'
}
[void][IO.Directory]::CreateDirectory($testRoot)

try {
    # Hard stops make an accidental process launch or portal call fail the test.
    function New-CampusHttpClient { throw 'Tests must not contact a live portal.' }
    function Start-Process { throw 'Tests must not start a live process.' }
    $script:testMonitorRunning = $false
    $script:testMonitorProcessValid = $true
    $script:testStartupForeign = $false
    $script:testStartupInfo = [pscustomobject]@{ Exists = $false; Owned = $false; Enabled = $false; Legacy = $false }
    function Test-CampusMonitorRunning([string]$ProjectRoot) { return $script:testMonitorRunning }
    function Test-CampusMonitorProcess([string]$ProjectRoot, [int]$ProcessId) { return $script:testMonitorProcessValid }
    function Get-CampusStartupInfo([string]$ProjectRoot) {
        if ($script:testStartupForeign) { return [pscustomobject]@{ Exists = $true; Owned = $false; Enabled = $false; Legacy = $false } }
        return $script:testStartupInfo
    }

    $paths = Get-CampusPaths -ProjectRoot $testRoot
    Assert-Service ($paths.Root -eq $testRoot) 'Project paths use the supplied isolated root'
    Assert-Service ($paths.Credential -eq (Join-Path $testRoot 'data\credential.xml')) 'Credential path remains inside the selected project'
    Assert-Service ($paths.Status -eq (Join-Path $testRoot 'data\status.json')) 'Status path remains inside the selected project'
    Assert-Service ($paths.Preferences -eq (Join-Path $testRoot 'data\ui-settings.json')) 'UI preference path remains inside the selected project'
    $identity = Get-CampusMonitorIdentity -ProjectRoot $testRoot
    $sameIdentity = Get-CampusMonitorIdentity -ProjectRoot ($testRoot + '\.')
    $otherIdentity = Get-CampusMonitorIdentity -ProjectRoot ($testRoot + '-other')
    Assert-Service ($identity.Key -eq $sameIdentity.Key) 'Equivalent root paths use the same monitor identity'
    Assert-Service ($identity.Key -ne $otherIdentity.Key -and $identity.StopName -ne $otherIdentity.StopName) 'Separate project copies cannot stop each other'
    Assert-Service ($identity.MutexName -ne $identity.StopName -and $identity.StopName -ne $identity.CheckName) 'Run, stop, and immediate-check signals use distinct names'

    $preferences = Get-CampusUiPreferences -ProjectRoot $testRoot
    Assert-Service ([bool]$preferences.MonitorOnLaunch) 'Monitoring is enabled by default when the UI launches'
    Set-CampusUiPreferences -ProjectRoot $testRoot -MonitorOnLaunch $false | Out-Null
    Assert-Service (-not (Get-CampusUiPreferences -ProjectRoot $testRoot).MonitorOnLaunch) 'Pausing monitoring persists across UI launches'
    Assert-Service (Test-Path -LiteralPath $paths.Preferences) 'Preferences are saved beneath the isolated data directory'
    Set-CampusUiPreferences -ProjectRoot $testRoot -MonitorOnLaunch $true | Out-Null
    Assert-Service ((Get-CampusUiPreferences -ProjectRoot $testRoot).MonitorOnLaunch) 'Monitoring preference can be re-enabled'
    $settingsText = [IO.File]::ReadAllText($paths.Preferences)
    Assert-Service ($settingsText -notmatch 'password|user_account|credential|https?://') 'UI settings contain no credentials or request URLs'

    $firstPassword = ConvertTo-SecureString 'service-test &+=?# password one' -AsPlainText -Force
    $nextPassword = ConvertTo-SecureString 'service-test second password' -AsPlainText -Force
    $emptyPassword = New-Object Security.SecureString
    Assert-ServiceThrows { Save-CampusUiCredential -ProjectRoot $testRoot -Account 'alpha' -Carrier 'unicom' -Password $emptyPassword } 'First account configuration requires a password'
    Assert-ServiceThrows { Save-CampusUiCredential -ProjectRoot $testRoot -Account ' ' -Carrier 'unicom' -Password $firstPassword } 'Blank account is rejected'
    Save-CampusUiCredential -ProjectRoot $testRoot -Account 'alpha' -Carrier 'unicom' -Password $firstPassword | Out-Null
    $saved = Read-CampusCredential $paths.Credential
    Assert-Service ($saved.UserName -eq 'alpha@unicom' -and $saved.GetNetworkCredential().Password -eq 'service-test &+=?# password one') 'UI account and carrier are combined without changing the password'
    $encrypted = [IO.File]::ReadAllText($paths.Credential)
    Assert-Service ($encrypted -notmatch 'service-test|password one') 'UI password is protected with Windows DPAPI'
    Save-CampusUiCredential -ProjectRoot $testRoot -Account 'alpha' -Carrier 'unicom' -Password $emptyPassword | Out-Null
    Assert-Service ((Read-CampusCredential $paths.Credential).GetNetworkCredential().Password -eq 'service-test &+=?# password one') 'Blank password preserves a previously saved identical full account'
    Assert-ServiceThrows { Save-CampusUiCredential -ProjectRoot $testRoot -Account 'beta' -Carrier 'unicom' -Password $emptyPassword } 'Changing account cannot inherit the previous password'
    Assert-ServiceThrows { Save-CampusUiCredential -ProjectRoot $testRoot -Account 'alpha' -Carrier 'cmcc' -Password $emptyPassword } 'Changing carrier cannot inherit the previous password'
    $saved = Read-CampusCredential $paths.Credential
    Assert-Service ($saved.UserName -eq 'alpha@unicom' -and $saved.GetNetworkCredential().Password -eq 'service-test &+=?# password one') 'Rejected account changes preserve the existing valid record'
    Save-CampusUiCredential -ProjectRoot $testRoot -Account 'beta' -Carrier 'telecom' -Password $nextPassword | Out-Null
    $saved = Read-CampusCredential $paths.Credential
    Assert-Service ($saved.UserName -eq 'beta@telecom' -and $saved.GetNetworkCredential().Password -eq 'service-test second password') 'A new password permits changing account and carrier together'
    Save-CampusUiCredential -ProjectRoot $testRoot -Account 'campus-student' -Carrier 'campus' -Password $firstPassword | Out-Null
    Assert-Service ((Read-CampusCredential $paths.Credential).UserName -eq 'campus-student') 'Campus carrier stores the base account without a suffix'
    [IO.File]::WriteAllText($paths.Credential, 'corrupt-test-account fake-secret https://example.invalid/?password=fake-secret')
    Assert-ServiceThrows { Save-CampusUiCredential -ProjectRoot $testRoot -Account 'campus-student' -Carrier 'campus' -Password $emptyPassword } 'A corrupt saved record cannot supply a retained password or expose its contents' 'fake-secret|corrupt-test-account|example.invalid'
    Save-CampusUiCredential -ProjectRoot $testRoot -Account 'repaired' -Carrier 'cmcc' -Password $nextPassword | Out-Null
    Assert-Service ((Read-CampusCredential $paths.Credential).UserName -eq 'repaired@cmcc') 'Supplying a new password repairs a corrupted account record'

    Assert-Service ((Resolve-CampusAccount ' alpha@unicom ' 'unicom') -eq 'alpha@unicom') 'Existing carrier suffix is preserved once and account whitespace is trimmed'
    Assert-ServiceThrows { Resolve-CampusAccount 'alpha@unicom' 'cmcc' } 'Conflicting explicit account suffix and carrier are rejected'
    Assert-ServiceThrows { Resolve-CampusAccount "alpha`r`ninjected" 'campus' } 'Control characters cannot be stored as an account'
    Assert-ServiceThrows { Resolve-CampusAccount 'alpha' 'unsupported' } 'Unknown carrier is rejected'
    $parts = Split-CampusAccount 'student@telecom'
    Assert-Service ($parts.Account -eq 'student' -and $parts.Carrier -eq 'telecom') 'Saved full accounts split into editable account and carrier'
    $parts = Split-CampusAccount 'campus-student'
    Assert-Service ($parts.Account -eq 'campus-student' -and $parts.Carrier -eq 'campus') 'Saved campus-only accounts retain the campus carrier'

    [IO.File]::WriteAllText($paths.Preferences, '{broken fake-secret')
    Assert-Service ((Get-CampusUiPreferences -ProjectRoot $testRoot).MonitorOnLaunch) 'Malformed UI preferences safely return the default'
    Set-CampusLocalJson $paths.Preferences @{ MonitorOnLaunch = 'false' }
    Assert-Service ((Get-CampusUiPreferences -ProjectRoot $testRoot).MonitorOnLaunch) 'Non-boolean preference values cannot silently change monitoring behavior'
    Set-CampusUiPreferences -ProjectRoot $testRoot -MonitorOnLaunch $true | Out-Null

    $view = Get-CampusAppViewModel -ProjectRoot $testRoot
    Assert-Service (-not $view.MonitorRunning -and $view.AuthState -eq 'Unknown' -and $view.MonitorState -eq 'Stopped') 'Missing live status never claims the account is online'
    Assert-Service ($view.CredentialAvailable -and $view.Account -eq 'repaired' -and $view.Carrier -eq 'cmcc') 'Unified settings load the locally saved account and carrier'
    Assert-Service ($null -eq $view.PSObject.Properties['Password'] -and $null -eq $view.PSObject.Properties['Credential']) 'The view model never returns a password or credential object'
    [IO.File]::WriteAllText($paths.Credential, 'broken-record fake-secret https://example.invalid')
    $view = Get-CampusAppViewModel -ProjectRoot $testRoot
    Assert-Service (-not $view.CredentialAvailable -and ($view | ConvertTo-Json) -notmatch 'fake-secret|broken-record|example.invalid') 'Corrupted credentials produce a safe settings state'
    Save-CampusUiCredential -ProjectRoot $testRoot -Account 'repaired' -Carrier 'cmcc' -Password $nextPassword | Out-Null

    $utcTime = [datetime]::UtcNow
    Assert-Service ((ConvertTo-CampusUtcTime $utcTime) -eq $utcTime) 'Typed UTC timestamps retain their timezone'
    Assert-Service ((ConvertTo-CampusUtcTime $utcTime.ToLocalTime()) -eq $utcTime) 'Typed local timestamps normalize to UTC'
    Assert-Service ((ConvertTo-CampusUtcTime '2026-10-18T12:34:56+08:00') -eq [datetime]::Parse('2026-10-18T04:34:56Z').ToUniversalTime()) 'Explicit offsets normalize to the same UTC instant'
    Assert-Service ($null -eq (ConvertTo-CampusUtcTime 'not-a-time')) 'Invalid timestamps safely return no time'

    $script:uncachedCredentialReader = (Get-Item Function:\Read-CampusCredential).ScriptBlock
    $uncachedStartupReader = (Get-Item Function:\Get-CampusStartupInfo).ScriptBlock
    $script:credentialReads = 0; $script:startupReads = 0
    function Read-CampusCredential([string]$Path) { $script:credentialReads++; return (& $script:uncachedCredentialReader $Path) }
    function Get-CampusStartupInfo([string]$ProjectRoot) { $script:startupReads++; return $script:testStartupInfo }
    try {
        $cache = @{}
        $view = Get-CampusAppViewModel $testRoot -Cache $cache
        1..20 | ForEach-Object { [void](Get-CampusAppViewModel $testRoot -Cache $cache) }
        Assert-Service ($script:credentialReads -eq 1 -and $script:startupReads -eq 1) 'Unchanged UI refreshes reuse account metadata and startup state without repeated decryption or COM reads'
        Assert-Service ($cache.LocalState.Value.Account -eq 'repaired' -and ($cache.LocalState.Value | ConvertTo-Json) -notmatch 'Password|Credential"|service-test') 'UI cache contains only display metadata, never passwords or credential objects'
        Save-CampusUiCredential -ProjectRoot $testRoot -Account 'cache-changed' -Carrier 'telecom' -Password $nextPassword | Out-Null
        $readsBefore = $script:credentialReads
        $view = Get-CampusAppViewModel $testRoot -Cache $cache
        Assert-Service ($view.Account -eq 'cache-changed' -and $view.Carrier -eq 'telecom' -and $script:credentialReads -eq $readsBefore + 1) 'Saving a changed account invalidates the cache on the next refresh'
        [IO.File]::WriteAllText($paths.Credential, 'broken-record fake-secret')
        Assert-Service (-not (Get-CampusAppViewModel $testRoot -Cache $cache).CredentialAvailable) 'Corrupting the credential record invalidates cached availability immediately'
        Remove-Item -LiteralPath $paths.Credential
        Assert-Service (-not (Get-CampusAppViewModel $testRoot -Cache $cache).CredentialAvailable) 'Deleting the credential record cannot leave cached availability enabled'
        Save-CampusUiCredential -ProjectRoot $testRoot -Account 'repaired' -Carrier 'cmcc' -Password $nextPassword | Out-Null
        Assert-Service ((Get-CampusAppViewModel $testRoot -Cache $cache).CredentialAvailable) 'Recreating a valid credential record restores availability immediately'
        $cache.LocalState.Age = [pscustomobject]@{ ElapsedMilliseconds = 30001 }
        $readsBefore = $script:credentialReads
        [void](Get-CampusAppViewModel $testRoot -Cache $cache)
        Assert-Service ($script:credentialReads -eq $readsBefore + 1) 'Cache lifetime is bounded even when file metadata is unchanged'
        $otherView = Get-CampusAppViewModel ($testRoot + '-other') -Cache $cache
        Assert-Service (-not $otherView.CredentialAvailable -and $otherView.Account -eq '') 'One project cannot reuse another project display cache'
    } finally {
        Set-Item Function:\Read-CampusCredential -Value $script:uncachedCredentialReader
        Set-Item Function:\Get-CampusStartupInfo -Value $uncachedStartupReader
    }

    $statusValues = @{
        MonitorState = 'Running'; AuthState = 'Online'; ReasonCode = 'Authenticated'
        Message = 'Test authentication confirmed'; Suggestion = 'Keep monitoring'; VpnActive = $true
        FailureCount = 0; LastLoginAt = [datetime]::UtcNow.ToString('o'); LastError = ''
        Account = 'fake-secret-account'; Password = 'fake-secret-password'
        Url = 'https://example.invalid/?password=fake-secret'; OwnerKey = 'untrusted-owner'; ProcessId = -1
        Config = @{ password = 'fake-secret' }; Terminal = @{ Ip = 'fake-terminal' }; Network = @{ Adapters = @('fake-network') }
    }
    Assert-Service (Write-CampusMonitorStatus -ProjectRoot $testRoot -Values $statusValues) 'Monitor status can be atomically saved in the isolated directory'
    $statusText = [IO.File]::ReadAllText($paths.Status)
    $record = Read-CampusLocalJson $paths.Status
    Assert-Service ($statusText -notmatch 'fake-secret|example.invalid|fake-terminal|fake-network|repaired') 'Status JSON omits accounts, passwords, request URLs, and raw network objects'
    Assert-Service ($record.OwnerKey -eq $identity.Key -and $record.ProcessId -eq $PID -and $record.SchemaVersion -eq 1) 'Status owner, process identity, and schema are set by the writer'
    $statusLock = [IO.File]::Open($paths.Status, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try {
        Assert-Service (-not (Write-CampusMonitorStatus -ProjectRoot $testRoot -Values $statusValues)) 'A locked UI status file cannot crash the network monitor'
    } finally { $statusLock.Dispose() }
    $script:testMonitorRunning = $true
    $view = Get-CampusAppViewModel -ProjectRoot $testRoot
    Assert-Service ($view.AuthState -eq 'Online' -and $view.MonitorRunning -and $view.VpnActive) 'A fresh status from the running monitor displays confirmed online state and VPN'
    $script:testMonitorRunning = $false
    $view = Get-CampusAppViewModel -ProjectRoot $testRoot
    Assert-Service ($view.AuthState -eq 'Unknown' -and $view.MonitorState -eq 'Stopped') 'A stopped monitor cannot display cached status as currently online'
    $script:testMonitorRunning = $true
    $record.UpdatedAt = [datetime]::UtcNow.AddMinutes(-2).ToString('o')
    Set-CampusLocalJson $paths.Status $record
    Assert-Service ((Get-CampusAppViewModel -ProjectRoot $testRoot).AuthState -eq 'Unknown') 'Expired monitor status is never shown as currently online'
    $record.UpdatedAt = [datetime]::UtcNow.AddMinutes(2).ToString('o')
    Set-CampusLocalJson $paths.Status $record
    Assert-Service ((Get-CampusAppViewModel -ProjectRoot $testRoot).AuthState -eq 'Unknown') 'Implausibly future-dated status is rejected'
    $record.UpdatedAt = [datetime]::UtcNow.ToString('o'); $record.OwnerKey = 'other-project'
    $record.LastError = 'foreign-project-error'
    Set-CampusLocalJson $paths.Status $record
    $view = Get-CampusAppViewModel -ProjectRoot $testRoot
    Assert-Service ($view.AuthState -eq 'Unknown' -and $view.LastError -eq '' -and $view.UpdatedAt -eq '') 'Another project copy cannot provide this monitor status, timestamps, or error history'
    $record.OwnerKey = $identity.Key
    Set-CampusLocalJson $paths.Status $record
    $script:testMonitorProcessValid = $false
    Assert-Service ((Get-CampusAppViewModel -ProjectRoot $testRoot).AuthState -eq 'Unknown') 'Status from an absent or unexpected process is rejected'
    $script:testMonitorProcessValid = $true
    $record.ProcessId = 'not-an-integer'
    Set-CampusLocalJson $paths.Status $record
    Assert-Service ((Get-CampusAppViewModel -ProjectRoot $testRoot).AuthState -eq 'Unknown') 'An invalid process ID in status JSON safely falls back to unknown'
    $record.ProcessId = '9999999999999999999999999'
    Set-CampusLocalJson $paths.Status $record
    Assert-Service ((Get-CampusAppViewModel -ProjectRoot $testRoot).AuthState -eq 'Unknown') 'An overflowing process ID in status JSON safely falls back to unknown'
    [IO.File]::WriteAllText($paths.Status, '{broken fake-secret')
    Assert-Service ((Get-CampusAppViewModel -ProjectRoot $testRoot).AuthState -eq 'Unknown') 'Malformed status JSON safely falls back to unknown'
    [void](Write-CampusMonitorStatus -ProjectRoot $testRoot -Values @{ MonitorState = 'Error'; AuthState = 'Online'; ReasonCode = 'CredentialRejected'; Message = 'Check locally saved credentials'; LastError = 'Account requires attention' })
    $script:testMonitorRunning = $false; $script:testMonitorProcessValid = $false
    $view = Get-CampusAppViewModel -ProjectRoot $testRoot
    Assert-Service (-not $view.MonitorRunning -and $view.AuthState -eq 'Unknown' -and $view.MonitorState -eq 'Error' -and $view.LastError -eq 'Account requires attention') 'A terminated monitor retains actionable errors without claiming the account is online'
    $script:testMonitorProcessValid = $true
    Assert-Service (@(Get-ChildItem -LiteralPath $paths.Data -Filter '*.tmp').Count -eq 0) 'Atomic settings and status writes leave no temporary files behind'

    $startupArguments = Get-CampusStartupArguments -ProjectRoot $testRoot
    $legacyArguments = Get-CampusStartupArguments -ProjectRoot $testRoot -Legacy
    Assert-Service ($startupArguments -match '-STA' -and $startupArguments -match '-StartHidden' -and $startupArguments.Contains(('"' + $paths.Tray + '"'))) 'Startup arguments launch the tray in STA mode with a quoted script path'
    Assert-Service (Test-CampusStartupOwnership -ProjectRoot $testRoot -TargetPath (Get-CampusPowerShellPath) -Arguments $startupArguments) 'Startup ownership recognizes this project tray shortcut'
    Assert-Service (Test-CampusStartupOwnership -ProjectRoot $testRoot -TargetPath (Get-CampusPowerShellPath) -Arguments $legacyArguments) 'Startup ownership recognizes this project legacy monitor shortcut for migration'
    Assert-Service (-not (Test-CampusStartupOwnership -ProjectRoot ($testRoot + '-other') -TargetPath (Get-CampusPowerShellPath) -Arguments $startupArguments)) 'Another project copy cannot claim or overwrite this startup shortcut'
    Assert-Service (-not (Test-CampusStartupOwnership -ProjectRoot $testRoot -TargetPath 'C:\unrelated.exe' -Arguments $startupArguments)) 'A different executable cannot be claimed as this project startup shortcut'
    Assert-Service (-not (Test-CampusStartupOwnership -ProjectRoot $testRoot -TargetPath (Get-CampusPowerShellPath) -Arguments ($startupArguments + ' -UnexpectedArgument'))) 'Unexpected startup arguments fail ownership validation'
    $script:testStartupForeign = $true
    Assert-ServiceThrows { Set-CampusStartup -ProjectRoot $testRoot -Enabled $true } 'A foreign same-name startup shortcut cannot be overwritten'
    Assert-ServiceThrows { Set-CampusStartup -ProjectRoot $testRoot -Enabled $false } 'A foreign same-name startup shortcut cannot be deleted'
    $script:testStartupForeign = $false
    $script:testStartupUpdates = 0
    function Set-CampusStartup([string]$ProjectRoot, [bool]$Enabled) {
        if ($ProjectRoot -ne $testRoot -or -not $Enabled) { throw 'Unexpected startup migration target.' }
        $script:testStartupUpdates++
    }
    $script:testStartupInfo = [pscustomobject]@{ Exists = $true; Owned = $true; Enabled = $true; Legacy = $true }
    Update-CampusStartupIfNeeded -ProjectRoot $testRoot
    Assert-Service ($script:testStartupUpdates -eq 1) 'An owned legacy shortcut is migrated to the tray startup entry'
    $script:testStartupInfo.Legacy = $false
    Update-CampusStartupIfNeeded -ProjectRoot $testRoot
    Assert-Service ($script:testStartupUpdates -eq 1) 'An up-to-date tray startup entry is not rewritten'
    $script:testStartupInfo = [pscustomobject]@{ Exists = $true; Owned = $false; Enabled = $false; Legacy = $true }
    Update-CampusStartupIfNeeded -ProjectRoot $testRoot
    Assert-Service ($script:testStartupUpdates -eq 1) 'A foreign legacy startup entry is not migrated'
    $script:testStartupInfo = [pscustomobject]@{ Exists = $false; Owned = $false; Enabled = $false; Legacy = $false }
    $script:testLegacyQueries = 0
    function Get-CimInstance([string]$ClassName, [string]$Filter, [string]$ErrorAction) {
        $script:testLegacyQueries++
        return @()
    }
    Stop-CampusOwnedLegacyMonitor -ProjectRoot $testRoot
    Assert-Service ($script:testLegacyQueries -eq 1) 'Legacy migration with no matching process does not signal any live monitor'

    $script:testPortQueries = New-Object 'Collections.Generic.List[int]'
    function Test-CampusTcpPort([int]$Port, [int]$TimeoutMilliseconds = 1500) {
        $script:testPortQueries.Add($Port)
        return [pscustomobject]@{ Port = $Port; Reachable = ($Port -eq 80); Code = $(if ($Port -eq 80) { 'Connected' } else { 'ConnectionRefused' }) }
    }
    $testNetwork = [pscustomobject]@{ Known = $true; HasLink = $true; HasIpv4 = $true; HasGateway = $true; VpnActive = $true }
    $testSnapshot = New-CampusSnapshot 'Unknown' 'RequestTimeout' $testNetwork -Terminal @{ password = 'fake-secret' } -Config @{ password = 'fake-secret' }
    $diagnosticText = Get-CampusDiagnosticText $testSnapshot
    Assert-Service ($script:testPortQueries.Count -eq 2 -and $script:testPortQueries[0] -eq 80 -and $script:testPortQueries[1] -eq 801) 'Unified diagnosis checks both portal TCP ports through the safe probe boundary'
    Assert-Service ($diagnosticText -match 'RequestTimeout' -and $diagnosticText -match '801' -and $diagnosticText -match 'ConnectionRefused' -and $diagnosticText -match '10.10.102.50/32' -and $diagnosticText -notmatch 'fake-secret') 'Unified diagnosis retains safe reasons and VPN guidance without serializing raw snapshots'
    $testNetwork.HasLink = $false; $testNetwork.HasIpv4 = $false
    $testSnapshot = New-CampusSnapshot 'Unknown' 'NoLocalLink' $testNetwork
    $diagnosticText = Get-CampusDiagnosticText $testSnapshot
    Assert-Service ($script:testPortQueries.Count -eq 2 -and $diagnosticText -match 'NoLocalLink') 'Unified diagnosis skips network probes until the local link and address are ready'

    [IO.File]::WriteAllText($paths.Log, "first line`r`nsecond line`r`nthird line`r`n", (New-Object Text.UTF8Encoding($true)))
    $recentLog = Get-CampusRecentLog -ProjectRoot $testRoot -Lines 2
    Assert-Service ($recentLog -notmatch 'first line' -and $recentLog -match 'second line' -and $recentLog -match 'third line') 'The log viewer returns only the requested recent lines'
    Assert-Service ((Get-CampusRecentLog -ProjectRoot $testRoot -Lines 0) -eq 'third line') 'The log viewer bounds a zero line request to one line'
    $missingLog = Get-CampusRecentLog -ProjectRoot ($testRoot + '-missing') -Lines 10
    Assert-Service (-not [string]::IsNullOrWhiteSpace($missingLog)) 'A missing log has a friendly empty state'

    $exitedProcess = [pscustomobject]@{ HasExited = $true }
    Assert-Service (-not (Wait-CampusMonitorReady -Process $exitedProcess -ProjectRoot $testRoot -TimeoutMilliseconds 100)) 'A child process that already exited cannot be reported as ready'
    $readyEvent = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, $identity.StopName)
    try {
        Assert-Service (Wait-CampusMonitorReady -Process ([pscustomobject]@{ HasExited = $false }) -ProjectRoot $testRoot -TimeoutMilliseconds 100) 'A live child is ready when its isolated stop signal exists'
        Assert-Service (-not $readyEvent.WaitOne(0)) 'Waiting for readiness never requests the monitor to stop'
    } finally { $readyEvent.Dispose() }
    Assert-Service (-not (Wait-CampusMonitorReady -Process ([pscustomobject]@{ HasExited = $false }) -ProjectRoot $testRoot -TimeoutMilliseconds 20)) 'A child without its own readiness signal times out safely'

    # Record launch requests in memory. No PowerShell child process is started.
    $script:testLaunches = New-Object 'Collections.Generic.List[object]'
    $script:testReadyCalls = New-Object 'Collections.Generic.List[object]'
    $script:testReadyResult = $true
    $script:testProcess = [pscustomobject]@{ HasExited = $false; Disposed = $false; Killed = $false; Waited = $false }
    $script:testProcess | Add-Member ScriptMethod Dispose { $this.Disposed = $true }
    $script:testProcess | Add-Member ScriptMethod Kill { $this.Killed = $true; $this.HasExited = $true }
    $script:testProcess | Add-Member ScriptMethod WaitForExit { param($TimeoutMilliseconds); $this.Waited = $true; return $true }
    function Wait-CampusMonitorReady($Process, [string]$ProjectRoot, [int]$TimeoutMilliseconds = 4000) {
        $script:testReadyCalls.Add([pscustomobject]@{ Process = $Process; ProjectRoot = $ProjectRoot })
        return $script:testReadyResult
    }
    function Start-Process([string]$FilePath, [string]$ArgumentList, [string]$WorkingDirectory, [string]$WindowStyle, [switch]$PassThru) {
        $script:testLaunches.Add([pscustomobject]@{ FilePath = $FilePath; Arguments = $ArgumentList; WorkingDirectory = $WorkingDirectory; WindowStyle = $WindowStyle; PassThru = $PassThru.IsPresent })
        if ($PassThru) { return $script:testProcess }
    }
    [IO.File]::WriteAllText($paths.Main, '# Isolated no-op launch fixture. Never executed.')
    $script:testMonitorRunning = $false
    Start-CampusMonitor -ProjectRoot $testRoot
    $launch = $script:testLaunches[0]
    Assert-Service ($script:testLaunches.Count -eq 1 -and $launch.WindowStyle -eq 'Hidden' -and $launch.WorkingDirectory -eq $testRoot) 'Starting monitoring launches one hidden process in the selected project'
    Assert-Service ($launch.FilePath -eq (Get-CampusPowerShellPath) -and $launch.Arguments.Contains(('"' + $paths.Main + '"')) -and $launch.Arguments -match '-Mode Run -NonInteractive' -and $launch.Arguments -notmatch 'repaired|service-test') 'Monitor launch uses a quoted script path and keeps account credentials out of command-line arguments'
    Assert-Service ($launch.PassThru -and $script:testReadyCalls.Count -eq 1 -and [object]::ReferenceEquals($script:testReadyCalls[0].Process, $script:testProcess) -and $script:testProcess.Disposed -and -not $script:testProcess.Killed) 'Successful startup waits for its own process and releases its handle without terminating monitoring'
    $script:testMonitorRunning = $true
    Start-CampusMonitor -ProjectRoot $testRoot
    Assert-Service ($script:testLaunches.Count -eq 1) 'Starting an already running monitor does not spawn a duplicate process'
    $script:testMonitorRunning = $false; $script:testReadyResult = $false
    $script:testProcess.Disposed = $false
    Assert-ServiceThrows { Start-CampusMonitor -ProjectRoot $testRoot } 'A child that fails to initialize reports startup failure'
    Assert-Service ($script:testProcess.Killed -and $script:testProcess.Waited -and $script:testProcess.Disposed -and [object]::ReferenceEquals($script:testReadyCalls[1].Process, $script:testProcess)) 'A failed startup terminates and releases only the process created by that request'
    $script:testProcess.Disposed = $false; $script:testProcess.Killed = $false; $script:testProcess.Waited = $false
    Assert-ServiceThrows { Start-CampusMonitor -ProjectRoot $testRoot } 'An already exited child still reports startup failure'
    Assert-Service ($script:testProcess.Disposed -and -not $script:testProcess.Killed -and -not $script:testProcess.Waited) 'Failure cleanup never tries to terminate an already exited child'
    $script:testReadyResult = $true; $script:testProcess.Disposed = $false; $script:testProcess.HasExited = $false
    $diagnosticTask = Start-CampusDiagnostic -ProjectRoot $testRoot
    $launch = $script:testLaunches[$script:testLaunches.Count - 1]
    Assert-Service ($diagnosticTask.ResultPath.StartsWith(($paths.Data + '\'), [StringComparison]::OrdinalIgnoreCase) -and $launch.Arguments.Contains(('"' + $diagnosticTask.ResultPath + '"')) -and $launch.Arguments -match '-Mode DiagnoseJson' -and $launch.WindowStyle -eq 'Hidden' -and $launch.PassThru) 'Background diagnosis uses an isolated quoted result file and a hidden process'
    Assert-Service ($null -eq (Get-CampusDiagnosticResult -Task $diagnosticTask) -and -not $script:testProcess.Disposed) 'Pending diagnostic work returns immediately without blocking the settings window'
    Set-CampusLocalJson $diagnosticTask.ResultPath @{ Success = $true; Text = 'Completed mock child result' }
    Assert-Service ($null -eq (Get-CampusDiagnosticResult -Task $diagnosticTask) -and -not $script:testProcess.Disposed) 'An in-progress diagnostic retains its result and handle until the child exits'
    $script:testProcess.HasExited = $true
    $result = Get-CampusDiagnosticResult -Task $diagnosticTask
    Assert-Service ($result.Success -and $script:testProcess.Disposed -and -not (Test-Path -LiteralPath $diagnosticTask.ResultPath)) 'Completed background diagnosis releases the process handle and temporary result'

    $racePath = Join-Path $paths.Data 'diagnostic-exit-race.json'
    $raceProcess = [pscustomobject]@{ Disposed = $false; ResultPath = $racePath }
    $raceProcess | Add-Member ScriptProperty HasExited {
        Set-CampusLocalJson $this.ResultPath @{ Success = $true; Text = 'Final result arrived during process check' }
        return $true
    }
    $raceProcess | Add-Member ScriptMethod Dispose { $this.Disposed = $true }
    $raceTask = [pscustomobject]@{ Process = $raceProcess; ResultPath = $racePath }
    $result = Get-CampusDiagnosticResult $raceTask
    Assert-Service ($result.Success -and $result.Text -eq 'Final result arrived during process check' -and $raceProcess.Disposed -and -not (Test-Path -LiteralPath $racePath)) 'A result written as the diagnostic exits is read instead of discarded'

    $script:testProcess.HasExited = $false; $script:testProcess.Killed = $false; $script:testProcess.Disposed = $false
    $timeoutTask = Start-CampusDiagnostic -ProjectRoot $testRoot
    $timeoutTask.Timer = [pscustomobject]@{ ElapsedMilliseconds = 60001 }
    Set-CampusLocalJson $timeoutTask.ResultPath @{ Success = $true; Text = 'Incomplete work' }
    $result = Get-CampusDiagnosticResult $timeoutTask
    Assert-Service (-not $result.Success -and $result.Text -match '60' -and $script:testProcess.Killed -and $script:testProcess.Disposed -and -not (Test-Path -LiteralPath $timeoutTask.ResultPath)) 'A hung diagnostic times out, cleans its own child, and never reports incomplete work as success'

    $resultPath = Join-Path $paths.Data 'diagnostic-test.json'
    $task = [pscustomobject]@{ Process = $null; ResultPath = $resultPath }
    Set-CampusLocalJson $resultPath @{ Success = $true; Text = 'Safe diagnostic result' }
    $result = Get-CampusDiagnosticResult -Task $task
    Assert-Service ($result.Success -and $result.Text -eq 'Safe diagnostic result' -and -not (Test-Path -LiteralPath $resultPath)) 'Completed diagnostic results are displayed and their temporary file is removed'
    [IO.File]::WriteAllText($resultPath, '{broken fake-secret https://example.invalid')
    $result = Get-CampusDiagnosticResult -Task $task
    Assert-Service (-not $result.Success -and $result.Text -notmatch 'fake-secret|example.invalid' -and -not (Test-Path -LiteralPath $resultPath)) 'Broken diagnostic output fails safely without leaking raw contents'
    $result = Get-CampusDiagnosticResult -Task $task
    Assert-Service (-not $result.Success -and -not [string]::IsNullOrWhiteSpace($result.Text)) 'Missing completed diagnostic output returns a safe failure'

    $stopEvent = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, $identity.StopName)
    $checkEvent = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, $identity.CheckName)
    try {
        Request-CampusMonitorCheck -ProjectRoot $testRoot
        Assert-Service ($checkEvent.WaitOne(0) -and -not $stopEvent.WaitOne(0)) 'Immediate check signals only the selected project check event'
        Stop-CampusMonitor -ProjectRoot $testRoot
        Assert-Service ($stopEvent.WaitOne(0)) 'Pause signals only the selected project stop event'
        [void]$stopEvent.Reset()
        Clear-CampusUiCredential -ProjectRoot $testRoot
        Assert-Service ($stopEvent.WaitOne(0) -and -not (Test-Path -LiteralPath $paths.Credential)) 'Clearing saved credentials stops the isolated monitor and removes its local record'
        Assert-Service (-not (Get-CampusUiPreferences -ProjectRoot $testRoot).MonitorOnLaunch) 'Clearing credentials disables automatic monitoring on UI launch'
    } finally { $stopEvent.Dispose(); $checkEvent.Dispose() }
    Stop-CampusMonitor -ProjectRoot $testRoot
    Assert-ServiceThrows { Request-CampusMonitorCheck -ProjectRoot $testRoot } 'Checking a stopped monitor returns a safe user-facing error'

    Write-Host ('All ' + $script:serviceChecks + ' service checks passed. Only isolated fake credentials were used; no live network, process, or startup settings were changed.')
} finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    if ($resolvedTestRoot.StartsWith(($publishRoot.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedTestRoot) -match '^test-service-[0-9a-f]{32}$' -and
        (Test-Path -LiteralPath $resolvedTestRoot)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
