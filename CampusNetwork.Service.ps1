. (Join-Path $PSScriptRoot 'CampusNetwork.Core.ps1')

function Get-CampusPaths([string]$ProjectRoot = $PSScriptRoot) {
    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
    $data = Join-Path $root 'data'
    return [pscustomobject]@{
        Root = $root; Data = $data; Credential = (Join-Path $data 'credential.xml')
        Status = (Join-Path $data 'status.json'); Preferences = (Join-Path $data 'ui-settings.json')
        Log = (Join-Path $data 'reconnect.log'); Main = (Join-Path $root 'CampusNetwork.ps1')
        Tray = (Join-Path $root 'CampusNetwork.Tray.ps1')
        Startup = (Join-Path ([Environment]::GetFolderPath('Startup')) 'CampusNetworkReconnect.lnk')
    }
}

function Get-CampusMonitorIdentity([string]$ProjectRoot = $PSScriptRoot) {
    $root = (Get-CampusPaths $ProjectRoot).Root.ToLowerInvariant()
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $key = [BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($root))).Replace('-', '').Substring(0, 16) }
    finally { $hasher.Dispose() }
    $suffix = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value + '_' + $key
    return [pscustomobject]@{
        Key = $key; MutexName = 'Local\CampusReconnectMutex_' + $suffix
        StopName = 'Local\CampusReconnectStop_' + $suffix; CheckName = 'Local\CampusReconnectCheck_' + $suffix
    }
}

function Read-CampusLocalJson([string]$Path) {
    try { return ([IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

function Set-CampusLocalJson([string]$Path, $Value) {
    $directory = [IO.Path]::GetDirectoryName($Path)
    if (-not (Test-Path -LiteralPath $directory)) { [void][IO.Directory]::CreateDirectory($directory) }
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($true)))
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}

function Get-CampusUiPreferences([string]$ProjectRoot = $PSScriptRoot) {
    $settings = Read-CampusLocalJson (Get-CampusPaths $ProjectRoot).Preferences
    $enabled = Get-CampusField $settings 'MonitorOnLaunch' $true
    if ($enabled -isnot [bool]) { $enabled = $true }
    return [pscustomobject]@{ MonitorOnLaunch = $enabled }
}

function Set-CampusUiPreferences([string]$ProjectRoot = $PSScriptRoot, [bool]$MonitorOnLaunch = $true) {
    Set-CampusLocalJson (Get-CampusPaths $ProjectRoot).Preferences ([ordered]@{ SchemaVersion = 1; MonitorOnLaunch = $MonitorOnLaunch })
}

function Split-CampusAccount([string]$Account) {
    if ($Account -match '^(.*)@(unicom|cmcc|telecom)$') { return [pscustomobject]@{ Account = $Matches[1]; Carrier = $Matches[2].ToLowerInvariant() } }
    return [pscustomobject]@{ Account = $Account; Carrier = 'campus' }
}

function Resolve-CampusAccount([string]$Account, [string]$Carrier) {
    $accountValue = $Account.Trim()
    if ([string]::IsNullOrWhiteSpace($accountValue) -or $accountValue -notmatch '^[a-zA-Z0-9._@-]+$') { throw '请输入有效的校园网账号。' }
    if ($Carrier -notin @('campus', 'unicom', 'cmcc', 'telecom')) { throw '请选择有效的运营商。' }
    $parts = Split-CampusAccount $accountValue
    if ($parts.Carrier -ne 'campus') {
        if ($parts.Carrier -ne $Carrier) { throw '账号后缀与所选运营商不一致。' }
        return $accountValue
    }
    if ($Carrier -eq 'campus') { return $accountValue }
    return $accountValue + '@' + $Carrier
}

function Save-CampusUiCredential([string]$ProjectRoot = $PSScriptRoot, [string]$Account, [string]$Carrier, [securestring]$Password) {
    $paths = Get-CampusPaths $ProjectRoot
    $fullAccount = Resolve-CampusAccount $Account $Carrier
    if ($null -eq $Password -or $Password.Length -eq 0) {
        try { $existing = Read-CampusCredential $paths.Credential } catch { throw '首次保存或更换账号、运营商时，请输入密码。' }
        if (-not [string]::Equals($existing.UserName, $fullAccount, [StringComparison]::Ordinal)) { throw '更换账号或运营商时，请重新输入密码。' }
        $Password = $existing.Password
    }
    if (-not (Test-Path -LiteralPath $paths.Data)) { [void][IO.Directory]::CreateDirectory($paths.Data) }
    Save-CampusCredential $paths.Credential (New-Object Management.Automation.PSCredential($fullAccount, $Password))
}

function Test-CampusMonitorRunning([string]$ProjectRoot = $PSScriptRoot) {
    $mutex = $null; $taken = $false
    try {
        $mutex = [Threading.Mutex]::OpenExisting((Get-CampusMonitorIdentity $ProjectRoot).MutexName)
        try { $taken = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $taken = $true }
        return -not $taken
    } catch [Threading.WaitHandleCannotBeOpenedException] { return $false }
    finally { if ($null -ne $mutex) { if ($taken) { $mutex.ReleaseMutex() }; $mutex.Dispose() } }
}

function Stop-CampusMonitor([string]$ProjectRoot = $PSScriptRoot) {
    try {
        $event = [Threading.EventWaitHandle]::OpenExisting((Get-CampusMonitorIdentity $ProjectRoot).StopName)
        try { [void]$event.Set() } finally { $event.Dispose() }
    } catch [Threading.WaitHandleCannotBeOpenedException] { }
}

function Request-CampusMonitorCheck([string]$ProjectRoot = $PSScriptRoot) {
    try {
        $event = [Threading.EventWaitHandle]::OpenExisting((Get-CampusMonitorIdentity $ProjectRoot).CheckName)
        try { [void]$event.Set() } finally { $event.Dispose() }
    } catch { throw '监测尚未启动，请先启动监测或使用网络诊断。' }
}

function Get-CampusPowerShellPath { return Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }

function Wait-CampusMonitorReady($Process, [string]$ProjectRoot, [int]$TimeoutMilliseconds = 4000) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        try {
            $event = [Threading.EventWaitHandle]::OpenExisting((Get-CampusMonitorIdentity $ProjectRoot).StopName)
            $event.Dispose()
            return $true
        } catch [Threading.WaitHandleCannotBeOpenedException] { }
        if ($Process.HasExited) { return $false }
        Start-Sleep -Milliseconds 50
    } while ($timer.ElapsedMilliseconds -lt $TimeoutMilliseconds)
    return $false
}

function Start-CampusMonitor([string]$ProjectRoot = $PSScriptRoot) {
    $paths = Get-CampusPaths $ProjectRoot
    [void](Read-CampusCredential $paths.Credential)
    if (-not (Test-Path -LiteralPath $paths.Main)) { throw '程序文件不完整，请重新下载完整项目。' }
    if (Test-CampusMonitorRunning $ProjectRoot) { return }
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $paths.Main + '" -Mode Run -NonInteractive'
    $process = Start-Process -FilePath (Get-CampusPowerShellPath) -ArgumentList $arguments -WorkingDirectory $paths.Root -WindowStyle Hidden -PassThru
    try {
        if (-not (Wait-CampusMonitorReady $process $ProjectRoot)) {
            if (-not $process.HasExited) { $process.Kill(); [void]$process.WaitForExit(2000) }
            throw '监测启动失败，请检查程序文件和账号配置后重试。'
        }
    } finally { $process.Dispose() }
}

function Write-CampusMonitorStatus([string]$ProjectRoot = $PSScriptRoot, [System.Collections.IDictionary]$Values) {
    $record = [ordered]@{ SchemaVersion = 1; OwnerKey = (Get-CampusMonitorIdentity $ProjectRoot).Key; ProcessId = $PID; UpdatedAt = [datetime]::UtcNow.ToString('o') }
    foreach ($name in @('MonitorState', 'AuthState', 'ReasonCode', 'Message', 'Suggestion', 'VpnActive', 'FailureCount', 'NextAttemptUtc', 'LastLoginAt', 'LastError')) {
        if ($Values.Contains($name)) { $record[$name] = $Values[$name] }
    }
    try { Set-CampusLocalJson (Get-CampusPaths $ProjectRoot).Status $record; return $true } catch { return $false }
}

function Test-CampusMonitorProcess([string]$ProjectRoot, [int]$ProcessId) {
    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        return $process.ProcessName -in @('powershell', 'pwsh')
    } catch { return $false }
}

function Get-CampusStartupArguments([string]$ProjectRoot = $PSScriptRoot, [switch]$Legacy) {
    $paths = Get-CampusPaths $ProjectRoot
    if ($Legacy) { return '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $paths.Main + '" -Mode Run -NonInteractive' }
    return '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "' + $paths.Tray + '" -StartHidden'
}

function Test-CampusStartupOwnership([string]$ProjectRoot, [string]$TargetPath, [string]$Arguments) {
    if (-not [string]::Equals($TargetPath, (Get-CampusPowerShellPath), [StringComparison]::OrdinalIgnoreCase)) { return $false }
    return [string]::Equals($Arguments.Trim(), (Get-CampusStartupArguments $ProjectRoot), [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($Arguments.Trim(), (Get-CampusStartupArguments $ProjectRoot -Legacy), [StringComparison]::OrdinalIgnoreCase)
}

function Get-CampusStartupInfo([string]$ProjectRoot = $PSScriptRoot) {
    $path = (Get-CampusPaths $ProjectRoot).Startup
    if (-not (Test-Path -LiteralPath $path)) { return [pscustomobject]@{ Exists = $false; Owned = $false; Enabled = $false; Legacy = $false } }
    $shell = $null; $shortcut = $null
    try {
        $shell = New-Object -ComObject WScript.Shell; $shortcut = $shell.CreateShortcut($path)
        $owned = Test-CampusStartupOwnership $ProjectRoot $shortcut.TargetPath $shortcut.Arguments
        return [pscustomobject]@{ Exists = $true; Owned = $owned; Enabled = $owned; Legacy = $owned -and $shortcut.Arguments -eq (Get-CampusStartupArguments $ProjectRoot -Legacy) }
    } catch { return [pscustomobject]@{ Exists = $true; Owned = $false; Enabled = $false; Legacy = $false } }
    finally {
        if ($null -ne $shortcut) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
        if ($null -ne $shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
    }
}

function Set-CampusStartup([string]$ProjectRoot = $PSScriptRoot, [bool]$Enabled) {
    $paths = Get-CampusPaths $ProjectRoot; $info = Get-CampusStartupInfo $ProjectRoot
    if ($info.Exists -and -not $info.Owned) { throw '同名启动项属于其他位置的程序，请先在原项目中取消启动项。' }
    if (-not $Enabled) { if ($info.Exists) { Remove-Item -LiteralPath $paths.Startup -Force }; return }
    [void](Read-CampusCredential $paths.Credential)
    if (-not (Test-Path -LiteralPath $paths.Tray)) { throw '托盘程序文件缺失，请重新下载完整项目。' }
    $shell = $null; $shortcut = $null
    try {
        $shell = New-Object -ComObject WScript.Shell; $shortcut = $shell.CreateShortcut($paths.Startup)
        $shortcut.TargetPath = Get-CampusPowerShellPath
        $shortcut.Arguments = Get-CampusStartupArguments $ProjectRoot
        $shortcut.WorkingDirectory = $paths.Root; $shortcut.Description = 'Campus network tray assistant'
        $shortcut.Save()
    } finally {
        if ($null -ne $shortcut) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
        if ($null -ne $shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
    }
}

function Get-CampusAppViewModel([string]$ProjectRoot = $PSScriptRoot) {
    $paths = Get-CampusPaths $ProjectRoot; $identity = Get-CampusMonitorIdentity $ProjectRoot
    $running = Test-CampusMonitorRunning $ProjectRoot
    $record = Read-CampusLocalJson $paths.Status
    $valid = $false; $updated = [datetime]::MinValue; $recordProcessId = 0
    if ($null -ne $record -and (Get-CampusField $record 'OwnerKey') -eq $identity.Key -and
        [datetime]::TryParse([string](Get-CampusField $record 'UpdatedAt'), [ref]$updated)) {
        $age = ([datetime]::UtcNow - $updated.ToUniversalTime()).TotalSeconds
        $hasProcessId = [int]::TryParse([string](Get-CampusField $record 'ProcessId' 0), [ref]$recordProcessId) -and $recordProcessId -gt 0
        $valid = $age -ge -60 -and $age -le 45 -and $hasProcessId -and (Test-CampusMonitorProcess $ProjectRoot $recordProcessId)
    }
    $auth = 'Unknown'; $state = if ($running) { 'Starting' } else { 'Stopped' }
    $status = if ($running) { '正在检查网络' } else { '监测已暂停' }
    $detail = if ($running) { '正在等待监测结果。' } else { '可启动监测，或使用网络诊断只读检查连接。' }
    $suggestion = ''; $vpn = $false
    if ($running -and $valid) {
        $auth = [string](Get-CampusField $record 'AuthState' 'Unknown')
        $state = [string](Get-CampusField $record 'MonitorState' 'Running')
        $detail = [string](Get-CampusField $record 'Message'); $suggestion = [string](Get-CampusField $record 'Suggestion')
        $vpn = [bool](Get-CampusField $record 'VpnActive' $false)
        $status = if ($state -eq 'LoggingIn') { '正在登录' } elseif ($state -eq 'RetryWaiting') { '等待重试' }
            elseif ($state -eq 'Error') { '需要处理' } elseif ($auth -eq 'Online') { '校园网已连接' }
            elseif ($auth -eq 'Offline') { '校园网未登录' } else { '网络连接异常' }
    }
    if (-not $running -and (Get-CampusField $record 'OwnerKey') -eq $identity.Key -and (Get-CampusField $record 'MonitorState') -eq 'Error') {
        $state = 'Error'; $status = '需要处理'
        $detail = [string](Get-CampusField $record 'Message')
        $suggestion = [string](Get-CampusField $record 'Suggestion')
    }
    $account = ''; $carrier = 'unicom'; $credentialAvailable = $false
    try {
        $credential = Read-CampusCredential $paths.Credential
        $parts = Split-CampusAccount $credential.UserName
        $account = $parts.Account; $carrier = $parts.Carrier; $credentialAvailable = $true
    } catch { }
    $startup = Get-CampusStartupInfo $ProjectRoot
    return [pscustomobject]@{
        MonitorRunning = $running; AuthState = $auth; MonitorState = $state; StatusText = $status
        DetailText = $detail; Suggestion = $suggestion; VpnActive = $vpn
        UpdatedAt = [string](Get-CampusField $record 'UpdatedAt'); LastLoginAt = [string](Get-CampusField $record 'LastLoginAt')
        LastError = [string](Get-CampusField $record 'LastError'); StartupEnabled = $startup.Enabled
        CredentialAvailable = $credentialAvailable; Account = $account; Carrier = $carrier
        MonitorOnLaunch = (Get-CampusUiPreferences $ProjectRoot).MonitorOnLaunch
    }
}

function Get-CampusRecentLog([string]$ProjectRoot = $PSScriptRoot, [int]$Lines = 100) {
    try { return ((Get-Content -LiteralPath (Get-CampusPaths $ProjectRoot).Log -Tail ([Math]::Min(500, [Math]::Max(1, $Lines))) | ForEach-Object { '{0}' -f $_ }) -join [Environment]::NewLine) }
    catch { return '暂无运行日志。' }
}

function Start-CampusDiagnostic([string]$ProjectRoot = $PSScriptRoot) {
    $paths = Get-CampusPaths $ProjectRoot
    if (-not (Test-Path -LiteralPath $paths.Data)) { [void][IO.Directory]::CreateDirectory($paths.Data) }
    $resultPath = Join-Path $paths.Data ('diagnostic-' + [guid]::NewGuid().ToString('N') + '.json')
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $paths.Main + '" -Mode DiagnoseJson -ResultPath "' + $resultPath + '"'
    $process = Start-Process -FilePath (Get-CampusPowerShellPath) -ArgumentList $arguments -WorkingDirectory $paths.Root -WindowStyle Hidden -PassThru
    return [pscustomobject]@{ Process = $process; ResultPath = $resultPath }
}

function Get-CampusDiagnosticResult($Task) {
    if (Test-Path -LiteralPath $Task.ResultPath) {
        $result = Read-CampusLocalJson $Task.ResultPath
        if ($null -ne $result -and $null -ne $result.PSObject.Properties['Text']) {
            Remove-Item -LiteralPath $Task.ResultPath -Force
            if ($null -ne $Task.Process) { $Task.Process.Dispose() }
            return [pscustomobject]@{ Success = [bool](Get-CampusField $result 'Success' $false); Text = [string]$result.Text }
        }
    }
    if ($null -ne $Task.Process -and -not $Task.Process.HasExited) { return $null }
    if (Test-Path -LiteralPath $Task.ResultPath) { Remove-Item -LiteralPath $Task.ResultPath -Force }
    if ($null -ne $Task.Process) { $Task.Process.Dispose() }
    return [pscustomobject]@{ Success = $false; Text = '诊断未能完成，请稍后重试。' }
}

function Clear-CampusUiCredential([string]$ProjectRoot = $PSScriptRoot) {
    Stop-CampusMonitor $ProjectRoot
    Set-CampusUiPreferences $ProjectRoot -MonitorOnLaunch $false
    $path = (Get-CampusPaths $ProjectRoot).Credential
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}

function Get-CampusDiagnosticText($Snapshot) {
    $lines = New-Object 'Collections.Generic.List[string]'
    $lines.Add((Format-CampusDiagnostic $Snapshot))
    $lines.Add(('VPN 隧道启用：' + $Snapshot.VpnActive))
    $lines.Add('认证请求已禁用系统 HTTP 代理。')
    if ($Snapshot.Network.Known -and $Snapshot.Network.HasLink -and $Snapshot.Network.HasIpv4) {
        $ports = @(Test-CampusTcpPort 80; Test-CampusTcpPort 801)
        foreach ($port in $ports) { $lines.Add(('认证地址 10.10.102.50 端口 ' + $port.Port + '：' + $port.Code)) }
        if ($ports[0].Reachable -and -not $ports[1].Reachable) { $lines.Add('网页登录端口 80 可达，但认证端口 801 不可达。请核对直连规则是否覆盖所有端口，以及校园网服务或防火墙设置。') }
    } else { $lines.Add('本地连接或地址尚未就绪，跳过端口探测。') }
    return $lines -join [Environment]::NewLine
}

function Stop-CampusOwnedLegacyMonitor([string]$ProjectRoot = $PSScriptRoot, [int]$WaitMilliseconds = 0) {
    $paths = Get-CampusPaths $ProjectRoot
    try {
        $pattern = '(?i)-File\s+"' + [regex]::Escape($paths.Main) + '"(?:\s|$)'
        $legacy = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop | Where-Object {
            $_.ProcessId -ne $PID -and $_.CommandLine -match $pattern -and $_.CommandLine -match '(?i)-Mode\s+Run(?:\s|$)'
        })
        if ($legacy.Count -eq 0) { return }
        $sidValue = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $event = [Threading.EventWaitHandle]::OpenExisting('Local\CampusReconnectStop_' + $sidValue)
        try { [void]$event.Set() } finally { $event.Dispose() }
        if ($WaitMilliseconds -gt 0) {
            $mutex = [Threading.Mutex]::OpenExisting('Local\CampusReconnectMutex_' + $sidValue)
            $taken = $false
            try {
                try { $taken = $mutex.WaitOne($WaitMilliseconds) } catch [Threading.AbandonedMutexException] { $taken = $true }
                if (-not $taken) { throw '旧版监测仍在退出，请稍后重新启动。' }
            } finally { if ($taken) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
        }
    } catch [Threading.WaitHandleCannotBeOpenedException] { }
}

function Update-CampusStartupIfNeeded([string]$ProjectRoot = $PSScriptRoot) {
    $info = Get-CampusStartupInfo $ProjectRoot
    if ($info.Owned -and $info.Legacy) { Set-CampusStartup $ProjectRoot -Enabled $true }
}
