[CmdletBinding()]
param(
    [ValidateSet('Run', 'Setup', 'Check', 'Stop', 'EnableStartup', 'DisableStartup', 'Forget')]
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
    $credential | Export-Clixml -LiteralPath $credentialPath -Encoding UTF8
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
        'Stop' { Send-CampusStop; exit 0 }
        'Forget' {
            Send-CampusStop
            if (Test-Path -LiteralPath $credentialPath) { Remove-Item -LiteralPath $credentialPath -Force }
            Write-Host '已删除本机保存的账号密码。'
            exit 0
        }
        'EnableStartup' {
            if (-not (Test-Path -LiteralPath $credentialPath)) { throw '请先运行“首次配置.cmd”。' }
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
    if ($Mode -eq 'Check') {
        try {
            $snapshot = Get-CampusSnapshot $client
            switch ($snapshot.State) {
                'Online' { Write-Host '校园网认证状态：已登录。'; exit 0 }
                'Offline' { Write-Host '校园网认证状态：未登录，可运行自动重连工具。'; exit 0 }
                default { Write-Host '无法确认校园网认证状态。请检查 Wi-Fi、VPN/代理或登录页是否可访问。'; exit 2 }
            }
        } finally { $client.Dispose() }
    }

    $mutex = New-Object Threading.Mutex($false, $mutexName)
    $ownsMutex = $false
    $stop = $null
    try {
        try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
        if (-not $ownsMutex) { Write-Host '自动重连工具已经在运行。'; exit 0 }
        if (-not (Test-Path -LiteralPath $credentialPath)) {
            if ($NonInteractive) { Write-CampusLog '缺少账号配置，请运行首次配置。'; exit 2 }
            Set-CampusCredential
        }
        try { $credential = Import-Clixml -LiteralPath $credentialPath } catch { throw '无法解密已保存的账号密码，请用当前 Windows 用户重新运行首次配置。' }
        if ($credential -isnot [pscredential]) { throw '账号配置文件无效，请重新运行首次配置。' }
        $stop = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, $stopName)
        [void]$stop.Reset()
        $state = New-CampusMonitorState
        $lastStatus = ''
        Write-CampusLog '自动重连已启动：每 30 秒检查认证，连续两次未认证才提交登录。'
        while (-not $stop.WaitOne(0)) {
            $snapshot = Get-CampusSnapshot $client
            if ($snapshot.State -ne $lastStatus) {
                $message = switch ($snapshot.State) { 'Online' { '已认证，保持监测。' } 'Offline' { '未认证，等待第二次确认。' } default { '认证接口不可用或状态不明确，等待网络恢复。' } }
                Write-CampusLog $message
                $lastStatus = $snapshot.State
            }
            $action = Get-CampusAction $state $snapshot.State ([datetime]::UtcNow)
            if ($action -eq 'Login' -and -not $stop.WaitOne(0)) {
                # Refresh once more before submitting, to avoid racing a manual login.
                $snapshot = Get-CampusSnapshot $client
                if ($snapshot.State -ne 'Offline') { [void](Get-CampusAction $state $snapshot.State ([datetime]::UtcNow)); continue }
                Write-CampusLog '确认认证已失效，尝试重新登录。'
                $login = Invoke-CampusLogin $client $snapshot $credential
                if ($login.Stop) { Write-CampusLog $login.Reason; break }
                if ($login.Accepted) {
                    if ($stop.WaitOne(3000)) { break }
                    $verify = Get-CampusSnapshot $client
                    if ($verify.State -eq 'Online') {
                        [void](Get-CampusAction $state 'Online' ([datetime]::UtcNow))
                        $lastStatus = 'Online'
                        Write-CampusLog '重新登录成功，认证状态已复核。'
                    } else {
                        $delay = Set-CampusFailure $state ([datetime]::UtcNow)
                        Write-CampusLog ('登录提交完成，但尚未确认恢复；' + $delay + ' 秒后再试。')
                    }
                } else {
                    $delay = Set-CampusFailure $state ([datetime]::UtcNow)
                    Write-CampusLog ($login.Reason + ' ' + $delay + ' 秒后再试。')
                }
            }
            if ($stop.WaitOne(30000)) { break }
        }
        Write-CampusLog '自动重连已停止。'
    } finally {
        if ($null -ne $stop) { $stop.Dispose() }
        if ($ownsMutex) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
        $client.Dispose()
    }
} catch {
    Write-Host ('工具未能继续运行：' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
