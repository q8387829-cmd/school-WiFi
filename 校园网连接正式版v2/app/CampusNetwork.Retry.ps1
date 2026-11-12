# Retry policy is separate from network I/O so recovery can be tested offline.
function New-CampusMonitorState {
    return [pscustomobject]@{
        Failures = 0; NextAttempt = [datetime]::MinValue; UnclassifiedRejections = 0
        HoldReason = ''; CredentialRevision = ''; LastAttempt = [datetime]::MinValue
        RecoveryUntil = [datetime]::MinValue; RecoveryAvailableAfter = [datetime]::MinValue; FastRetries = 0
        RateLimitUntil = [datetime]::MinValue; SafetyUntil = [datetime]::MinValue
        LocalFingerprint = $null; LastManualCheck = [datetime]::MinValue
    }
}

function Get-CampusCredentialRevision([string]$Path) {
    $file = New-Object IO.FileInfo($Path)
    if ($file.Exists) { return ('{0}:{1}:{2}' -f $file.CreationTimeUtc.Ticks, $file.LastWriteTimeUtc.Ticks, $file.Length) }
    return ''
}

function Get-CampusAction($State, [string]$Status, [datetime]$Now, [string]$CredentialRevision = '') {
    $replaced = $CredentialRevision -and $State.CredentialRevision -and $CredentialRevision -ne $State.CredentialRevision
    if ($CredentialRevision) { $State.CredentialRevision = $CredentialRevision }
    if ($Status -eq 'Online' -or $replaced) {
        $State.Failures = 0; $State.NextAttempt = [datetime]::MinValue
        $State.UnclassifiedRejections = 0; $State.HoldReason = ''; $State.SafetyUntil = [datetime]::MinValue
        if ($Status -eq 'Online') { $State.RecoveryUntil = [datetime]::MinValue }
        # Changing an account cannot bypass a server rate limit.
        if ($State.RateLimitUntil -gt $Now) { $State.NextAttempt = $State.RateLimitUntil }
    }
    if ($Status -eq 'Offline' -and -not $State.HoldReason -and $Now -ge $State.NextAttempt -and
        $Now -ge $State.RateLimitUntil -and $Now -ge $State.SafetyUntil) { return 'Login' }
    return 'Wait'
}

function Request-CampusRecovery($State, [string]$Reason, [datetime]$Now) {
    if ($State.HoldReason) { return $false }
    $opened = $false
    if ($Reason -in @('Startup', 'Resumed', 'LocalNetworkChanged') -and $Now -ge $State.RecoveryAvailableAfter) {
        $State.RecoveryUntil = $Now.AddSeconds(90)
        $State.RecoveryAvailableAfter = $Now.AddSeconds(120)
        $State.FastRetries = 0
        $opened = $true
    }
    if ($Reason -eq 'ManualCheck') {
        if (($Now - $State.LastManualCheck).TotalSeconds -lt 5) { return $false }
        $State.LastManualCheck = $Now
    }
    # Event storms do not extend a recovery window, replenish its budget, or
    # erase failures. Manual checks also respect explicit holds and cooldowns.
    if ($opened -or $Reason -eq 'ManualCheck') {
        $earliest = $Now
        foreach ($limit in @($State.LastAttempt.AddSeconds(3), $State.RateLimitUntil, $State.SafetyUntil)) {
            if ($limit -gt $earliest) { $earliest = $limit }
        }
        if ($State.NextAttempt -gt $earliest) { $State.NextAttempt = $earliest }
    }
    return $opened
}

function Update-CampusRecoveryNetwork($State, $Network, [datetime]$Now) {
    if (-not $Network.Known) { return $false }
    $fingerprint = [string]$Network.LocalFingerprint
    $changed = $null -ne $State.LocalFingerprint -and $State.LocalFingerprint -ne $fingerprint
    $State.LocalFingerprint = $fingerprint
    if ($changed -and $Network.HasLink -and $Network.HasIpv4) {
        [void](Request-CampusRecovery $State 'LocalNetworkChanged' $Now)
        return $true
    }
    return $false
}

function Set-CampusRateLimit($State, [datetime]$Now, [int]$RetryAfterSeconds = 60) {
    $until = $Now.AddSeconds([Math]::Max(60, $RetryAfterSeconds))
    if ($until -gt $State.RateLimitUntil) { $State.RateLimitUntil = $until }
    if ($State.RateLimitUntil -gt $State.NextAttempt) { $State.NextAttempt = $State.RateLimitUntil }
    return [int][Math]::Ceiling(($State.RateLimitUntil - $Now).TotalSeconds)
}

function Set-CampusFailure($State, [datetime]$Now) {
    $State.Failures++
    if ($State.UnclassifiedRejections -ge 3) {
        # Unknown refusals remain recoverable, without submitting continuously.
        $delay = 300
        $State.SafetyUntil = $Now.AddSeconds($delay)
    } elseif ($Now -lt $State.RecoveryUntil -and $State.FastRetries -lt 3) {
        $delay = @(3, 5, 10)[$State.FastRetries]
        $State.FastRetries++
    } else {
        $delay = @(15, 30, 60, 120, 300)[[Math]::Min(4, $State.Failures - 1)]
    }
    $State.NextAttempt = $Now.AddSeconds($delay)
    if ($State.RateLimitUntil -gt $State.NextAttempt) { $State.NextAttempt = $State.RateLimitUntil }
    return [int][Math]::Ceiling(($State.NextAttempt - $Now).TotalSeconds)
}

function Set-CampusLoginRejection($State, $Login, [datetime]$Now) {
    if ($Login.Stop) {
        $State.HoldReason = $Login.Reason
        $State.NextAttempt = [datetime]::MinValue
        return 0
    }
    if ((Get-CampusField $Login 'Code') -eq 'RateLimited' -or (Get-CampusField $Login 'Kind') -eq 'RateLimited') {
        return (Set-CampusRateLimit $State $Now (Get-CampusField $Login 'RetryAfterSeconds' 60))
    }
    if (-not (Get-CampusField $Login 'Submitted' $true)) {
        # DHCP/link changes before submission are not credential failures.
        $State.NextAttempt = $Now.AddSeconds(2)
        return 2
    }
    if ((Get-CampusField $Login 'Kind') -eq 'Unclassified') { $State.UnclassifiedRejections++ }
    return (Set-CampusFailure $State $Now)
}

function Get-CampusNextDelay($State, [datetime]$Now) {
    $delay = if ($Now -lt $State.RecoveryUntil) { 2000 } else { 5000 }
    if ($State.RateLimitUntil -gt $Now) { return 1000 }
    if ($State.NextAttempt -gt $Now) {
        $delay = [Math]::Min($delay, [Math]::Ceiling(($State.NextAttempt - $Now).TotalMilliseconds))
    }
    return [int][Math]::Max(100, $delay)
}
