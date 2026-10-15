[CmdletBinding()]
param(
    [ValidateSet('Run', 'Setup', 'Check', 'Diagnose', 'DiagnoseJson', 'CheckCredential', 'Stop', 'EnableStartup', 'DisableStartup', 'Forget')]
    [string]$Mode = 'Run',
    [switch]$NonInteractive,
    [string]$ResultPath
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CampusNetwork.Service.ps1')
$dataDirectory = Join-Path $PSScriptRoot 'data'
$credentialPath = Join-Path $dataDirectory 'credential.xml'
$logPath = Join-Path $dataDirectory 'reconnect.log'
$identity = Get-CampusMonitorIdentity $PSScriptRoot
$mutexName = $identity.MutexName
$stopName = $identity.StopName
$script:monitorStatus = [ordered]@{ MonitorState = 'Starting'; AuthState = 'Unknown'; Message = '正在启动监测。'; Suggestion = ''; LastLoginAt = ''; LastError = '' }

function Publish-CampusStatus([string]$Phase, $Snapshot = $null, $RetryState = $null) {
    $script:monitorStatus.MonitorState = $Phase
    if ($null -ne $Snapshot) {
        $script:monitorStatus.AuthState = $Snapshot.State
        $script:monitorStatus.ReasonCode = $Snapshot.ReasonCode
        $script:monitorStatus.Message = Format-CampusDiagnostic $Snapshot
        $script:monitorStatus.Suggestion = $Snapshot.Suggestion
        $script:monitorStatus.VpnActive = $Snapshot.VpnActive
        if ($Snapshot.State -eq 'Unknown') { $script:monitorStatus.LastError = Format-CampusDiagnostic $Snapshot }
    }
    if ($null -ne $RetryState) {
        $script:monitorStatus.FailureCount = $RetryState.Failures
        $script:monitorStatus.NextAttemptUtc = if ($RetryState.NextAttempt -gt [datetime]::MinValue) { $RetryState.NextAttempt.ToUniversalTime().ToString('o') } else { '' }
    }
    [void](Write-CampusMonitorStatus -ProjectRoot $PSScriptRoot -Values $script:monitorStatus)
}

function Write-CampusLog([string]$Message) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $Message
    Write-Host $line
    if (-not (Test-Path -LiteralPath $dataDirectory)) { New-Item -ItemType Directory -Path $dataDirectory | Out-Null }
    if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 1048576) {
        Move-Item -LiteralPath $logPath -Destination ($logPath + '.old') -Force
    }
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

function Set-CampusCredential {
    Write-Host '账号密码只在本机输入。密码以 Windows DPAPI 加密保存，仅当前 Windows 用户可解密。'
    $account = (Read-Host '校园网账号（不含运营商后缀）').Trim()
    if ([string]::IsNullOrWhiteSpace($account)) { throw '账号不能为空。' }
    if ($account -notmatch '@(unicom|cmcc|telecom)$') {
        Write-Host '1 校园网 / 2 中国联通 / 3 中国移动 / 4 中国电信'
        $carrier = (Read-Host '选择运营商（按回车默认中国联通）').Trim()
        if ($carrier -eq '') { $carrier = '2' }
        $suffix = switch ($carrier) { '1' { '' } '2' { '@unicom' } '3' { '@cmcc' } '4' { '@telecom' } default { throw '运营商选项无效。' } }
        $account += $suffix
    }
    $password = Read-Host '校园网密码（输入不显示）' -AsSecureString
    if ($password.Length -eq 0) { throw '密码不能为空。' }
    if (-not (Test-Path -LiteralPath $dataDirectory)) { New-Item -ItemType Directory -Path $dataDirectory | Out-Null }
    $credential = New-Object System.Management.Automation.PSCredential($account, $password)
    Save-CampusCredential $credentialPath $credential
    Write-Host '配置已保存。运行“启动自动重连.cmd”即可持续监测。'
}

function Send-CampusStop {
    Set-CampusUiPreferences -ProjectRoot $PSScriptRoot -MonitorOnLaunch $false
    Stop-CampusMonitor -ProjectRoot $PSScriptRoot
    Stop-CampusOwnedLegacyMonitor -ProjectRoot $PSScriptRoot
    Write-Host '已请求停止监测，并记住暂停状态。'
}

try {
    switch ($Mode) {
        'Setup' { Set-CampusCredential; exit 0 }
        'CheckCredential' {
            [void](Read-CampusCredential $credentialPath)
            Write-Host '账号记录正常：账号和密码已保存，当前 Windows 用户可以读取。'
            Write-Host '该检查不向校园网提交登录，也不显示账号或密码。'
            exit 0
        }
        'Stop' { Send-CampusStop; exit 0 }
        'Forget' {
            Send-CampusStop
            if (Test-Path -LiteralPath $credentialPath) { Remove-Item -LiteralPath $credentialPath -Force }
            Write-Host '已删除本机保存的账号密码。'
            exit 0
        }
        'EnableStartup' {
            Set-CampusStartup -ProjectRoot $PSScriptRoot -Enabled $true
            Write-Host '已设置当前 Windows 用户登录后启动。请保持本文件夹的位置不变。'
            exit 0
        }
        'DisableStartup' {
            Set-CampusStartup -ProjectRoot $PSScriptRoot -Enabled $false
            Write-Host '已取消开机启动。'
            exit 0
        }
    }
    $client = New-CampusHttpClient
    if ($Mode -in @('Check', 'Diagnose', 'DiagnoseJson')) {
        try {
            if ($Mode -eq 'DiagnoseJson') {
                $resultFullPath = [IO.Path]::GetFullPath($ResultPath)
                if ([IO.Path]::GetDirectoryName($resultFullPath) -ne [IO.Path]::GetFullPath($dataDirectory) -or
                    [IO.Path]::GetFileName($resultFullPath) -notmatch '^diagnostic-[a-f0-9]{32}\.json$') { throw '诊断结果位置无效。' }
            }
            $snapshot = Get-CampusSnapshot $client
            $diagnosticText = if ($Mode -eq 'Check') { Format-CampusDiagnostic $snapshot } else { Get-CampusDiagnosticText $snapshot }
            if ($Mode -eq 'DiagnoseJson') { Set-CampusLocalJson $resultFullPath ([ordered]@{ Success = $snapshot.State -ne 'Unknown'; Text = $diagnosticText }) }
            else { Write-Host $diagnosticText }
            if ($snapshot.State -eq 'Unknown') { exit 2 }
            exit 0
        } finally { $client.Dispose() }
    }

    $mutex = New-Object Threading.Mutex($false, $mutexName)
    $ownsMutex = $false
    $stop = $null
    $check = $null
    $watcher = $null
    try {
        try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
        if (-not $ownsMutex) { Write-Host '自动重连工具已经在运行。'; exit 0 }
        $stop = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, $stopName)
        [void]$stop.Reset()
        $check = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::AutoReset, $identity.CheckName)
        if (-not $NonInteractive) { Set-CampusUiPreferences -ProjectRoot $PSScriptRoot -MonitorOnLaunch $true }
        $previousStatus = Read-CampusLocalJson (Get-CampusPaths $PSScriptRoot).Status
        if ((Get-CampusField $previousStatus 'OwnerKey') -eq $identity.Key) {
            $script:monitorStatus.LastLoginAt = Get-CampusField $previousStatus 'LastLoginAt'
            $script:monitorStatus.LastError = Get-CampusField $previousStatus 'LastError'
        }
        Publish-CampusStatus 'Starting'
        Stop-CampusOwnedLegacyMonitor -ProjectRoot $PSScriptRoot -WaitMilliseconds 15000
        if (-not (Test-Path -LiteralPath $credentialPath)) {
            if ($NonInteractive) { Write-CampusLog '缺少账号配置，请运行首次配置。'; exit 2 }
            Set-CampusCredential
        }
        $credential = Read-CampusCredential $credentialPath
        $watcher = Start-CampusNetworkWatcher
        $state = New-CampusMonitorState
        $lastStatus = ''
        Write-CampusLog '账号记录读取正常。自动重连已启动：每 5 秒检查认证，首次确认未登录就立即提交登录；网络切换或唤醒后立即复查。'
        if ($watcher.Sources.Count -eq 0) { Write-CampusLog '系统事件监听不可用，继续使用定时查询和网卡变化检测。' }
        while (-not $stop.WaitOne(0)) {
            $snapshot = Get-CampusSnapshot $client
            $statusKey = $snapshot.State + '|' + $snapshot.ReasonCode + '|' + $snapshot.Stage + '|' + $snapshot.HttpStatus + '|' + $snapshot.VpnActive
            if ($statusKey -ne $lastStatus) {
                Write-CampusLog (Format-CampusDiagnostic $snapshot)
                $lastStatus = $statusKey
            }
            $action = Get-CampusAction $state $snapshot.State ([datetime]::UtcNow)
            $phase = if ($state.NextAttempt -gt [datetime]::UtcNow -and $snapshot.State -eq 'Offline') { 'RetryWaiting' } else { 'Running' }
            Publish-CampusStatus $phase $snapshot $state
            if ($action -eq 'Login' -and -not $stop.WaitOne(0)) {
                $credential = Read-CampusCredential $credentialPath
                Write-CampusLog '检测到认证已失效，立即使用最新保存的账号记录登录。'
                Publish-CampusStatus 'LoggingIn' $snapshot $state
                $login = Invoke-CampusLogin $client $snapshot $credential
                if ($login.Stop) {
                    Write-CampusLog $login.Reason
                    $script:monitorStatus.Message = $login.Reason; $script:monitorStatus.LastError = $login.Reason
                    $script:monitorStatus.Suggestion = '请在账号与设置中检查配置，或打开校园网登录页处理后，再启动监测。'
                    Publish-CampusStatus 'Error'
                    break
                }
                if ($login.Accepted) {
                    if ($stop.WaitOne(3000)) { break }
                    $verify = Get-CampusSnapshot $client
                    if ($verify.State -eq 'Online') {
                        [void](Get-CampusAction $state 'Online' ([datetime]::UtcNow))
                        $lastStatus = $verify.State + '|' + $verify.ReasonCode + '|' + $verify.Stage + '|' + $verify.HttpStatus + '|' + $verify.VpnActive
                        Write-CampusLog '重新登录成功，认证状态已复核。'
                        $script:monitorStatus.LastLoginAt = [datetime]::UtcNow.ToString('o')
                        Publish-CampusStatus 'Running' $verify $state
                    } else {
                        $delay = Set-CampusFailure $state ([datetime]::UtcNow)
                        Write-CampusLog ('登录提交完成，但尚未确认恢复；' + $delay + ' 秒后再试。 ' + (Format-CampusDiagnostic $verify))
                        $script:monitorStatus.LastError = '登录提交完成，但尚未确认恢复。'
                        Publish-CampusStatus 'RetryWaiting' $verify $state
                    }
                } else {
                    $delay = Set-CampusFailure $state ([datetime]::UtcNow)
                    Write-CampusLog ($login.Reason + ' ' + $delay + ' 秒后再试。')
                    $script:monitorStatus.LastError = $login.Reason
                    Publish-CampusStatus 'RetryWaiting' $snapshot $state
                }
            }
            $wakeReason = Wait-CampusNextCheck $stop $watcher $snapshot.Network.Fingerprint -CheckSignal $check
            if ($wakeReason -eq 'Stop') { break }
            if ($wakeReason -in @('NetworkChanged', 'Resumed')) {
                $freshNetwork = Get-CampusNetworkContext
                if ($wakeReason -eq 'Resumed' -or $freshNetwork.Fingerprint -ne $snapshot.Network.Fingerprint) {
                    $state.Failures = 0; $state.NextAttempt = [datetime]::MinValue
                }
                $client.Dispose()
                $client = New-CampusHttpClient
                $wakeMessage = if ($wakeReason -eq 'Resumed') { '检测到电脑唤醒，立即复查校园网认证。' } else { '检测到网卡或网络地址变化，立即复查校园网认证。' }
                Write-CampusLog $wakeMessage
            }
        }
        Write-CampusLog '自动重连已停止。'
    } catch {
        if ($ownsMutex) {
            $script:monitorStatus.Message = '监测未能继续，请检查账号记录或重新打开助手。'
            $script:monitorStatus.LastError = $script:monitorStatus.Message
            $script:monitorStatus.Suggestion = '请检查本机账号配置，并查看网络诊断结果。'
            Publish-CampusStatus 'Error'
        }
        throw
    } finally {
        if ($ownsMutex -and $script:monitorStatus.MonitorState -ne 'Error') {
            $script:monitorStatus.AuthState = 'Unknown'
            Publish-CampusStatus 'Stopped'
        }
        Stop-CampusNetworkWatcher $watcher
        if ($null -ne $check) { $check.Dispose() }
        if ($null -ne $stop) { $stop.Dispose() }
        if ($ownsMutex) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
        $client.Dispose()
    }
} catch {
    Write-Host ('工具未能继续运行：' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
