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
        if ($RetryState.HoldReason) {
            $script:monitorStatus.Message = $RetryState.HoldReason; $script:monitorStatus.LastError = $RetryState.HoldReason
            $script:monitorStatus.Suggestion = '监测仍在运行。请检查并保存账号或在网页登录；检测到账号记录更新或已上线后，会自动恢复。'
        }
        $script:monitorStatus.FailureCount = $RetryState.Failures
        $script:monitorStatus.NextAttemptUtc = if ($RetryState.NextAttempt -gt [datetime]::MinValue) { $RetryState.NextAttempt.ToUniversalTime().ToString('o') } else { '' }
        $script:monitorStatus.RecoveryUntilUtc = if ($RetryState.RecoveryUntil -gt [datetime]::UtcNow) { $RetryState.RecoveryUntil.ToUniversalTime().ToString('o') } else { '' }
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
    if ([string]::IsNullOrWhiteSpace($account) -or $account -notmatch '^[a-zA-Z0-9._@-]+$') { throw '请输入有效的校园网账号。' }
    if ($account -match '^(.+)@(unicom|cmcc|telecom)$') {
        $baseAccount = $Matches[1]
        $carrierSuffix = '@' + $Matches[2].ToLowerInvariant()
        if ($baseAccount -notmatch '^[a-zA-Z0-9._-]+$') { throw '请输入有效的校园网账号。' }
        $account = $baseAccount + $carrierSuffix
    } else {
        if ($account -notmatch '^[a-zA-Z0-9._-]+$') { throw '请输入有效的校园网账号。' }
        Write-Host '1 校园网 / 2 中国联通 / 3 中国移动 / 4 中国电信'
        $carrier = (Read-Host '选择运营商（按回车默认中国联通）').Trim()
        if ($carrier -eq '') { $carrier = '2' }
        $suffix = switch ($carrier) { '1' { '' } '2' { '@unicom' } '3' { '@cmcc' } '4' { '@telecom' } default { throw '运营商选项无效。' } }
        $account += $suffix
    }
    $password = Read-Host '校园网密码（输入不显示）' -AsSecureString
    if ($password.Length -eq 0) { $password.Dispose(); throw '密码不能为空。' }
    try {
        if (-not (Test-Path -LiteralPath $dataDirectory)) { New-Item -ItemType Directory -Path $dataDirectory | Out-Null }
        $credential = New-Object System.Management.Automation.PSCredential($account, $password)
        Save-CampusCredential $credentialPath $credential
    } finally {
        $password.Dispose()
    }
    Write-Host '配置已保存。打开根目录的“打开校园网助手.cmd”，在连接页面开启监测。'
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
            $checked = Read-CampusCredential $credentialPath
            $checked.Password.Dispose()
            Write-Host '账号记录正常：账号和密码已保存，当前 Windows 用户可以读取。'
            Write-Host '该检查不向校园网提交登录，也不显示账号或密码。'
            exit 0
        }
        'Stop' { Send-CampusStop; exit 0 }
        'Forget' {
            Send-CampusStop
            Clear-CampusUiCredential -ProjectRoot $PSScriptRoot
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
    $monitorFaulted = $false
    $stop = $null
    $check = $null
    $ready = $null
    $watcher = $null
    $credential = $null
    try {
        try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
        if (-not $ownsMutex) { Write-Host '自动重连工具已经在运行。'; exit 0 }
        $stop = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, $stopName)
        [void]$stop.Reset()
        $check = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::AutoReset, $identity.CheckName)
        $ready = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, $identity.ReadyName)
        [void]$ready.Reset()
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
        Write-CampusLog '正式版 v2 自动重连已启动：正常每 5 秒检查，唤醒/本地网络恢复后短间隔复查。'
        foreach ($eventName in @('NetworkAddressChanged', 'NetworkAvailabilityChanged', 'PowerModeChanged')) {
            Write-CampusLog ('[Watcher/' + $eventName + '] Enabled=' + $watcher.Sources.ContainsKey($eventName))
        }
        if (-not $watcher.Sources.ContainsKey('PowerModeChanged')) { Write-CampusLog '电源事件监听不可用，保留单调时间断层与本地网卡检测。' }
        if (-not $stop.WaitOne(0)) { [void]$ready.Set() }
        . (Join-Path $PSScriptRoot 'CampusNetwork.Monitor.ps1')
        Invoke-CampusMonitorLoop $stop $check $watcher $credentialPath
        Write-CampusLog '自动重连已停止。'
    } catch {
        $monitorFaulted = $true
        if ($ownsMutex) {
            $script:monitorStatus.Message = '监测未能继续，请检查账号记录或重新打开助手。'
            $script:monitorStatus.LastError = $script:monitorStatus.Message
            $script:monitorStatus.Suggestion = '请检查本机账号配置，并查看网络诊断结果。'
            Publish-CampusStatus 'Error'
        }
        throw
    } finally {
        if ($ownsMutex -and -not $monitorFaulted) {
            $script:monitorStatus.AuthState = 'Unknown'
            Publish-CampusStatus 'Stopped'
        }
        Stop-CampusNetworkWatcher $watcher
        if ($null -ne $credential) { $credential.Password.Dispose() }
        if ($null -ne $ready) { [void]$ready.Reset(); $ready.Dispose() }
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
