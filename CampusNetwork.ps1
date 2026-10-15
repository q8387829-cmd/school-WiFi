[CmdletBinding()]
param(
    [ValidateSet('Run', 'Setup', 'Check', 'Diagnose', 'CheckCredential', 'Stop', 'EnableStartup', 'DisableStartup', 'Forget')]
    [string]$Mode = 'Run',
    [switch]$NonInteractive
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CampusNetwork.Core.ps1')
$dataDirectory = Join-Path $PSScriptRoot 'data'
$credentialPath = Join-Path $dataDirectory 'credential.xml'
$logPath = Join-Path $dataDirectory 'reconnect.log'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$mutexName = 'Local\CampusReconnectMutex_' + $sid
$stopName = 'Local\CampusReconnectStop_' + $sid

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
    try {
        $event = [Threading.EventWaitHandle]::OpenExisting($stopName)
        try { [void]$event.Set(); Write-Host '已通知自动重连工具停止。' } finally { $event.Dispose() }
    } catch [Threading.WaitHandleCannotBeOpenedException] { Write-Host '当前没有正在运行的自动重连工具。' }
}

function Get-CampusStartupPath {
    return Join-Path ([Environment]::GetFolderPath('Startup')) 'CampusNetworkReconnect.lnk'
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
            [void](Read-CampusCredential $credentialPath)
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut((Get-CampusStartupPath))
            $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $PSScriptRoot 'CampusNetwork.ps1') + '" -Mode Run -NonInteractive'
            $shortcut.WorkingDirectory = $PSScriptRoot
            $shortcut.Description = 'Campus network automatic reauthentication'
            $shortcut.Save()
            Write-Host '已设置当前 Windows 用户登录后启动。请保持本文件夹的位置不变。'
            exit 0
        }
        'DisableStartup' {
            $shortcutPath = Get-CampusStartupPath
            if (Test-Path -LiteralPath $shortcutPath) { Remove-Item -LiteralPath $shortcutPath -Force }
            Write-Host '已取消开机启动。'
            exit 0
        }
    }
    $client = New-CampusHttpClient
    if ($Mode -in @('Check', 'Diagnose')) {
        try {
            $snapshot = Get-CampusSnapshot $client
            Write-Host (Format-CampusDiagnostic $snapshot)
            if ($Mode -eq 'Diagnose') {
                Write-Host ('VPN 隧道启用：' + $snapshot.VpnActive)
                Write-Host '认证请求已禁用系统 HTTP 代理。'
                if ($snapshot.Network.Known -and $snapshot.Network.HasLink -and $snapshot.Network.HasIpv4) {
                    $ports = @(Test-CampusTcpPort 80; Test-CampusTcpPort 801)
                    foreach ($port in $ports) {
                        Write-Host ('认证地址 10.10.102.50 端口 ' + $port.Port + '：' + $port.Code)
                    }
                    if ($ports[0].Reachable -and -not $ports[1].Reachable) {
                        Write-Host '网页登录端口 80 可达，但认证端口 801 不可达。请核对直连规则是否覆盖所有端口，以及校园网服务或防火墙设置。'
                    }
                } else { Write-Host '本地连接或地址尚未就绪，跳过端口探测。' }
            }
            if ($snapshot.State -eq 'Unknown') { exit 2 }
            exit 0
        } finally { $client.Dispose() }
    }

    $mutex = New-Object Threading.Mutex($false, $mutexName)
    $ownsMutex = $false
    $stop = $null
    $watcher = $null
    try {
        try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
        if (-not $ownsMutex) { Write-Host '自动重连工具已经在运行。'; exit 0 }
        if (-not (Test-Path -LiteralPath $credentialPath)) {
            if ($NonInteractive) { Write-CampusLog '缺少账号配置，请运行首次配置。'; exit 2 }
            Set-CampusCredential
        }
        $credential = Read-CampusCredential $credentialPath
        $stop = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, $stopName)
        [void]$stop.Reset()
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
            if ($action -eq 'Login' -and -not $stop.WaitOne(0)) {
                $credential = Read-CampusCredential $credentialPath
                Write-CampusLog '检测到认证已失效，立即使用最新保存的账号记录登录。'
                $login = Invoke-CampusLogin $client $snapshot $credential
                if ($login.Stop) { Write-CampusLog $login.Reason; break }
                if ($login.Accepted) {
                    if ($stop.WaitOne(3000)) { break }
                    $verify = Get-CampusSnapshot $client
                    if ($verify.State -eq 'Online') {
                        [void](Get-CampusAction $state 'Online' ([datetime]::UtcNow))
                        $lastStatus = $verify.State + '|' + $verify.ReasonCode + '|' + $verify.Stage + '|' + $verify.HttpStatus + '|' + $verify.VpnActive
                        Write-CampusLog '重新登录成功，认证状态已复核。'
                    } else {
                        $delay = Set-CampusFailure $state ([datetime]::UtcNow)
                        Write-CampusLog ('登录提交完成，但尚未确认恢复；' + $delay + ' 秒后再试。 ' + (Format-CampusDiagnostic $verify))
                    }
                } else {
                    $delay = Set-CampusFailure $state ([datetime]::UtcNow)
                    Write-CampusLog ($login.Reason + ' ' + $delay + ' 秒后再试。')
                }
            }
            $wakeReason = Wait-CampusNextCheck $stop $watcher $snapshot.Network.Fingerprint
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
    } finally {
        Stop-CampusNetworkWatcher $watcher
        if ($null -ne $stop) { $stop.Dispose() }
        if ($ownsMutex) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
        $client.Dispose()
    }
} catch {
    Write-Host ('工具未能继续运行：' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
