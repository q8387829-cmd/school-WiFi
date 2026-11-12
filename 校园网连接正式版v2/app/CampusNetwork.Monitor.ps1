# Single-threaded monitor: events and local network changes invalidate snapshots before login.
function Invoke-CampusMonitorLoop($Stop, $Check, $Watcher, [string]$CredentialPath) {
    $state = New-CampusMonitorState
    [void](Request-CampusRecovery $state 'Startup' ([datetime]::UtcNow))
    $client = New-CampusHttpClient
    $credential = $null
    $pending = ''
    $fingerprint = ''
    $lastStatus = ''
    $verificationPending = $false
    $verifyAfter = [datetime]::MinValue
    try {
        while (-not $Stop.WaitOne(0)) {
            $now = [datetime]::UtcNow
            $reason = Get-CampusPendingReason $Stop $Watcher $Check $pending
            $pending = ''
            if ($reason -eq 'Stop') { break }
            $network = Get-CampusNetworkContext
            $localChanged = Update-CampusRecoveryNetwork $state $network $now
            if ($reason -in @('Resumed', 'ClockGap')) {
                [void](Request-CampusRecovery $state 'Resumed' $now)
                Write-CampusLog ('[Wake/' + $reason + '] 检测到唤醒或请求时间断层，立即刷新并复查认证。')
            } elseif ($reason -eq 'ManualCheck') {
                [void](Request-CampusRecovery $state 'ManualCheck' $now)
                Write-CampusLog '[Check/ManualCheck] 收到立即检查请求；保留账号暂停和服务器冷却限制。'
            }
            if ($localChanged) { Write-CampusLog '[Wake/LocalNetworkChanged] 本地网络地址已变化，立即复查认证。' }
            if ($reason -in @('Resumed', 'ClockGap', 'NetworkChanged') -or $network.Fingerprint -ne $fingerprint) {
                $client.Dispose()
                $client = New-CampusHttpClient
            }
            $fingerprint = $network.Fingerprint
            # A 429 from any endpoint suppresses ALL authentication HTTP until expiry.
            if ($state.RateLimitUntil -gt $now) {
                $limited = New-CampusSnapshot 'Unknown' 'RateLimited' $network
                Publish-CampusStatus 'RetryWaiting' $limited $state
                $pending = Wait-CampusNextCheck $Stop $Watcher $fingerprint -DelayMilliseconds 1000 -CheckSignal $Check
                continue
            }
            if ($verificationPending -and $now -lt $verifyAfter) {
                $remaining = [int][Math]::Max(100, [Math]::Ceiling(($verifyAfter - $now).TotalMilliseconds))
                $pending = Wait-CampusNextCheck $Stop $Watcher $fingerprint -DelayMilliseconds $remaining -CheckSignal $Check
                continue
            }
            $snapshot = Get-CampusSnapshot $client -Network $network -StopSignal $Stop
            if ($Stop.WaitOne(0) -or $null -eq $snapshot) { break }
            if ($snapshot.ReasonCode -eq 'RateLimited') {
                $delay = Set-CampusRateLimit $state ([datetime]::UtcNow) $snapshot.RetryAfterSeconds
                Write-CampusLog ('[Retry/RateLimited] 所有认证请求暂停 ' + $delay + ' 秒。')
            }
            # A single request has a 10s timeout. A >15s gap is treated as stale,
            # not an ordinary 30s three-request snapshot or a wall-clock adjustment.
            if ($snapshot.ReasonCode -eq 'ResumeDetected') { $pending = 'ClockGap'; continue }
            $pending = Get-CampusPendingReason $Stop $Watcher $Check
            if ($pending -eq 'Stop') { break }
            $currentNetwork = Get-CampusNetworkContext
            if ($pending -in @('Resumed', 'NetworkChanged', 'ClockGap') -or $currentNetwork.Fingerprint -ne $fingerprint) {
                if ($pending -ne 'Resumed') { $pending = 'NetworkChanged' }
                continue
            }
            if ($pending -eq 'ManualCheck') {
                [void](Request-CampusRecovery $state 'ManualCheck' ([datetime]::UtcNow))
                Write-CampusLog '[Check/ManualCheck] 收到立即检查请求；当前认证检查已完成。'
                $pending = ''
            }
            $now = [datetime]::UtcNow
            if ($verificationPending -and $snapshot.ReasonCode -ne 'RateLimited') {
                $verificationPending = $false
                if ($snapshot.State -eq 'Online') {
                    $script:monitorStatus.LastLoginAt = $now.ToString('o')
                    $script:monitorStatus.LastError = ''
                    Write-CampusLog '重新登录成功，认证状态已复核。'
                } elseif ($snapshot.ReasonCode -ne 'RateLimited') {
                    $delay = Set-CampusFailure $state $now
                    $script:monitorStatus.LastError = '登录提交完成，但尚未确认恢复。'
                    Write-CampusLog ('[Retry/Verification] 登录提交完成但尚未确认恢复；' + $delay + ' 秒后再试。')
                }
            }
            $previousHold = $state.HoldReason
            $revision = Get-CampusCredentialRevision $CredentialPath
            $action = Get-CampusAction $state $snapshot.State $now $revision
            if ($previousHold -and -not $state.HoldReason) { Write-CampusLog '认证已恢复或账号记录已更新，已解除自动提交暂停。' }
            $statusKey = $snapshot.State + '|' + $snapshot.ReasonCode + '|' + $snapshot.Stage + '|' + $snapshot.HttpStatus + '|' + $snapshot.VpnActive
            if ($statusKey -ne $lastStatus) {
                if ($state.HoldReason) { Write-CampusLog ('[' + $snapshot.ReasonCode + '] 正在复查在线状态，自动提交仍暂停。') }
                else { Write-CampusLog (Format-CampusDiagnostic $snapshot) }
                $lastStatus = $statusKey
            }
            $phase = if ($state.HoldReason) { 'Error' }
                elseif ($state.NextAttempt -gt $now -and $snapshot.State -ne 'Online') { 'RetryWaiting' }
                elseif ($state.RecoveryUntil -gt $now -and $snapshot.State -ne 'Online') { 'Recovering' }
                else { 'Running' }
            Publish-CampusStatus $phase $snapshot $state
            if ($action -eq 'Login') {
                # Read and revision-check the account at the point of use.
                $beforeRead = Get-CampusCredentialRevision $CredentialPath
                $newCredential = $null
                if ($beforeRead) {
                    try { $newCredential = Read-CampusCredential $CredentialPath } catch { $newCredential = $null }
                }
                $afterRead = Get-CampusCredentialRevision $CredentialPath
                if (-not $beforeRead -or $null -eq $newCredential -or $beforeRead -ne $afterRead) {
                    if ($null -ne $newCredential) { $newCredential.Password.Dispose() }
                    $action = 'Wait'
                    Write-CampusLog '账号记录正在更新或不可读取，等待下一次检查后读取最新配置。'
                } else {
                    if ($null -ne $credential) { $credential.Password.Dispose() }
                    $credential = $newCredential
                    $action = Get-CampusAction $state $snapshot.State ([datetime]::UtcNow) $beforeRead
                }
            }
            if ($action -eq 'Login' -and -not $Stop.WaitOne(0)) {
                $pending = Get-CampusPendingReason $Stop $Watcher $Check
                if ($pending -eq 'Stop') { break }
                if ($pending -in @('Resumed', 'NetworkChanged', 'ClockGap')) { continue }
                $currentNetwork = Get-CampusNetworkContext
                if ($currentNetwork.Fingerprint -ne $fingerprint) { $pending = 'NetworkChanged'; continue }
                Write-CampusLog '检测到认证已失效，使用最新保存的账号记录登录。'
                Publish-CampusStatus 'LoggingIn' $snapshot $state
                $state.LastAttempt = [datetime]::UtcNow
                $login = Invoke-CampusLogin $client $snapshot $credential -Network $currentNetwork -StopSignal $Stop
                if ($Stop.WaitOne(0) -or $null -eq $login) { break }
                if ($login.Accepted) {
                    $verificationPending = $true
                    $verifyAfter = [datetime]::UtcNow.AddSeconds(3)
                    $state.NextAttempt = $verifyAfter
                } else {
                    $delay = Set-CampusLoginRejection $state $login ([datetime]::UtcNow)
                    if ($state.HoldReason) {
                        Write-CampusLog $state.HoldReason
                        Publish-CampusStatus 'Error' $snapshot $state
                    } else {
                        $kind = [string](Get-CampusField $login 'Kind' 'Transient')
                        $submitted = [bool](Get-CampusField $login 'Submitted' $false)
                        Write-CampusLog ('[Retry/' + $kind + '] Submitted=' + $submitted + '; FastRetries=' + $state.FastRetries + '/3; Delay=' + $delay + 's. ' + $login.Reason)
                        $script:monitorStatus.LastError = $login.Reason
                        if ((Get-CampusField $login 'Code') -eq 'ResumeDetected') { $pending = 'ClockGap' }
                        Publish-CampusStatus 'RetryWaiting' $snapshot $state
                    }
                }
            }
            if (-not $pending) {
                $wait = Get-CampusNextDelay $state ([datetime]::UtcNow)
                if ($verificationPending) { $wait = 3000 }
                $pending = Wait-CampusNextCheck $Stop $Watcher $fingerprint -DelayMilliseconds $wait -CheckSignal $Check
            }
        }
    } finally {
        if ($null -ne $credential) { $credential.Password.Dispose() }
        $client.Dispose()
    }
}
