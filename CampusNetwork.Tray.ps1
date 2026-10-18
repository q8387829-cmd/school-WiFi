[CmdletBinding()]
param(
    [switch]$StartHidden,
    [string]$PreviewPath,
    [ValidateSet('Status', 'Account', 'Diagnostics', 'Logs')]
    [string]$PreviewPage = 'Status'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'CampusNetwork.TrayView.ps1')

# All public screenshots use synthetic data and never initialize the service.
if (-not [string]::IsNullOrWhiteSpace($PreviewPath)) {
    $previewUi = New-CampusTrayView
    try {
        $sample = [pscustomobject]@{
            MonitorRunning = $true; AuthState = 'Online'; MonitorState = 'Running'
            StatusText = '校园网已连接'; DetailText = '认证状态正常，正在持续监测。检测到认证失效后会立即尝试登录。'
            Suggestion = '当前连接正常。开启 VPN 时，请将 10.10.102.50/32 设置为直连。'
            LastLoginAt = '2026-10-15T09:41:08'; LastError = ''; UpdatedAt = '2026-10-15T10:26:35'
            VpnActive = $true; StartupEnabled = $false; CredentialAvailable = $true
            Account = 'demo_student'; Carrier = 'unicom'; MonitorOnLaunch = $true
        }
        Set-CampusUiModel $previewUi $sample
        $previewUi.AccountTextBox.Text = 'demo_student'
        $previewUi.MonitorOnLaunchCheckBox.Checked = $true
        Set-CampusLogPresentation -TextBox $previewUi.LogTextBox -Text "2026-10-15 10:26:35  校园网已登录，监测继续运行。`r`n2026-10-15 09:41:08  自动登录成功。`r`n2026-10-15 09:41:05  检测到未登录，立即尝试认证。"
        Set-CampusUiDiagnostic -Ui $previewUi -Success $true -Text "网络诊断完成`r`n`r`n无线连接：正常`r`n认证地址：10.10.102.50`r`nHTTP 80 端口：可连接`r`n认证 801 端口：可连接`r`nVPN 隧道：已启用`r`n校园网认证：已登录`r`n`r`n建议：当前认证服务可访问，请保持校园网认证地址为直连。"
        Show-CampusUiPage $previewUi $PreviewPage
        $previewUi.Form.ShowInTaskbar = $false
        $previewUi.Form.Show()
        [void]$previewUi.Navigation[$PreviewPage].Focus()
        $previewUi.Form.Refresh()
        [Windows.Forms.Application]::DoEvents()
        $bitmap = New-Object Drawing.Bitmap($previewUi.Form.Width, $previewUi.Form.Height)
        try {
            $rectangle = New-Object Drawing.Rectangle(0, 0, $bitmap.Width, $bitmap.Height)
            $previewUi.Form.DrawToBitmap($bitmap, $rectangle)
            $bitmap.Save([IO.Path]::GetFullPath($PreviewPath), [Drawing.Imaging.ImageFormat]::Png)
        } finally { $bitmap.Dispose() }
    } finally { $previewUi.Form.Dispose() }
    exit 0
}

if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    [void][Windows.Forms.MessageBox]::Show('请使用项目中的“校园网助手.cmd”打开界面。', '校园网助手', 'OK', 'Information')
    exit 1
}

. (Join-Path $PSScriptRoot 'CampusNetwork.Service.ps1')

if (-not ('CampusNetwork.NativeIcon' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace CampusNetwork {
    public static class NativeIcon {
        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern bool DestroyIcon(IntPtr handle);
    }
}
'@
}

function New-CampusStateIcon([string]$State) {
    $color = '#34C759'
    if ($State -eq 'LoggingIn') { $color = '#007AFF' }
    if ($State -eq 'Error') { $color = '#FF9500' }
    if ($State -eq 'Stopped') { $color = '#8E8E93' }
    $bitmap = New-Object Drawing.Bitmap(32, 32)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $brush = New-Object Drawing.SolidBrush((ConvertTo-CampusColor $color))
    $pen = New-Object Drawing.Pen([Drawing.Color]::White, 2.7)
    $handle = [IntPtr]::Zero
    $temporary = $null
    try {
        $graphics.SmoothingMode = 'AntiAlias'
        $graphics.FillEllipse($brush, 1, 1, 30, 30)
        switch ($State) {
            'Stopped' {
                $graphics.DrawLine($pen, 12, 10, 12, 22)
                $graphics.DrawLine($pen, 20, 10, 20, 22)
            }
            'LoggingIn' {
                $graphics.DrawArc($pen, 8, 8, 16, 16, 20, 275)
                $graphics.DrawLine($pen, 23, 9, 23, 15)
                $graphics.DrawLine($pen, 23, 9, 17, 10)
            }
            'Error' {
                $graphics.DrawLine($pen, 16, 8, 16, 18)
                $graphics.DrawLine($pen, 16, 22, 16, 24)
            }
            default {
                $graphics.DrawLine($pen, 8, 16, 14, 22)
                $graphics.DrawLine($pen, 14, 22, 24, 10)
            }
        }
        $handle = $bitmap.GetHicon()
        $temporary = [Drawing.Icon]::FromHandle($handle)
        return $temporary.Clone()
    } finally {
        if ($null -ne $temporary) { $temporary.Dispose() }
        if ($handle -ne [IntPtr]::Zero) { [void][CampusNetwork.NativeIcon]::DestroyIcon($handle) }
        $pen.Dispose()
        $brush.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Set-CampusFeedback([string]$Text, [switch]$ErrorState) {
    $script:ui.FeedbackLabel.Text = $Text
    $script:ui.FeedbackLabel.ForeColor = ConvertTo-CampusColor '#636369'
    if ($ErrorState) { $script:ui.FeedbackLabel.ForeColor = ConvertTo-CampusColor '#A05A00' }
    $script:ui.ToolTips.SetToolTip($script:ui.FeedbackLabel, $Text)
}

function Show-CampusWindow([string]$Page = '') {
    if ($Page) { Show-CampusUiPage $script:ui $Page }
    $script:ui.Form.Show()
    $script:ui.Form.WindowState = 'Normal'
    [void]$script:ui.Form.Activate()
}

function Update-CampusTrayModel {
    try {
        $script:currentModel = Get-CampusAppViewModel -ProjectRoot $PSScriptRoot -Cache $script:modelCache
        Set-CampusUiModel $script:ui $script:currentModel
        $script:syncPreferences = $true
        try {
            $script:ui.StartupCheckBox.Checked = [bool]$script:currentModel.StartupEnabled
            $script:ui.MonitorOnLaunchCheckBox.Checked = [bool]$script:currentModel.MonitorOnLaunch
        } finally { $script:syncPreferences = $false }
        $script:menuMonitor.Text = $script:ui.ToggleMonitorButton.Text
        $script:menuCheck.Enabled = [bool]$script:currentModel.MonitorRunning
        $state = 'Error'
        if ($script:currentModel.AuthState -eq 'Online') { $state = 'Online' }
        if ($script:currentModel.MonitorState -eq 'LoggingIn') { $state = 'LoggingIn' }
        if ($script:currentModel.MonitorState -eq 'Error') { $state = 'Error' }
        if (-not $script:currentModel.MonitorRunning -and $script:currentModel.MonitorState -ne 'Error') { $state = 'Stopped' }
        if ($state -ne $script:iconState) {
            $script:notify.Icon = $script:stateIcons[$state]
            $script:ui.Form.Icon = $script:stateIcons[$state]
            $script:iconState = $state
        }
        $tooltip = '校园网助手 · ' + $script:ui.MonitorStateLabel.Text.Replace('自动监测：', '')
        if ($script:currentModel.AuthState -eq 'Online') { $tooltip += ' · 已连接' }
        if ($tooltip.Length -gt 63) { $tooltip = $tooltip.Substring(0, 63) }
        $script:notify.Text = $tooltip
    } catch {
        Set-CampusFeedback '暂时无法读取状态，请稍后重试或查看网络诊断。' -ErrorState
    }
}

function Invoke-CampusMonitorToggle {
    try {
        $model = Get-CampusAppViewModel -ProjectRoot $PSScriptRoot -Cache $script:modelCache
        if ($model.MonitorRunning) {
            Set-CampusUiPreferences -ProjectRoot $PSScriptRoot -MonitorOnLaunch $false
            [void](Stop-CampusMonitor -ProjectRoot $PSScriptRoot)
            Set-CampusFeedback '已请求暂停监测，正在等待后台停止。'
        } else {
            if (-not $model.CredentialAvailable) {
                Show-CampusWindow 'Account'
                Set-CampusFeedback '请先填写并保存校园网账号、运营商和密码。' -ErrorState
                [void]$script:ui.AccountTextBox.Focus()
                return
            }
            Set-CampusUiPreferences -ProjectRoot $PSScriptRoot -MonitorOnLaunch $true
            [void](Start-CampusMonitor -ProjectRoot $PSScriptRoot)
            Set-CampusFeedback '已启动自动监测。'
        }
        Update-CampusTrayModel
    } catch {
        Set-CampusFeedback '无法切换监测状态，请检查账号配置或稍后重试。' -ErrorState
    }
}

function Invoke-CampusCheckNow {
    try {
        [void](Request-CampusMonitorCheck -ProjectRoot $PSScriptRoot)
        Set-CampusFeedback '已通知后台立即检查，连接状态将自动更新。'
    } catch {
        Set-CampusFeedback '无法请求检查，请先启动监测。' -ErrorState
    }
}

function Update-CampusLogView {
    try {
        $text = Get-CampusRecentLog -ProjectRoot $PSScriptRoot -Lines 100
        if ([string]::IsNullOrWhiteSpace($text)) { $text = '暂无运行记录。' }
        $hasSelection = $script:ui.LogTextBox.SelectionLength -gt 0
        Set-CampusLogPresentation -TextBox $script:ui.LogTextBox -Text $text
        if (-not $hasSelection) {
            $script:ui.LogTextBox.SelectionStart = $script:ui.LogTextBox.TextLength
            $script:ui.LogTextBox.ScrollToCaret()
        }
        Set-CampusFeedback '已刷新最近 100 条日志。'
    } catch {
        Set-CampusFeedback '暂时无法读取日志，请稍后重试。' -ErrorState
    }
}

function Start-CampusUiDiagnostic {
    Show-CampusWindow 'Diagnostics'
    if ($null -ne $script:diagnosticTask) { return }
    try {
        $script:diagnosticTask = Start-CampusDiagnostic -ProjectRoot $PSScriptRoot
        $script:ui.DiagnosisButton.Enabled = $false
        $script:ui.DiagnosisButton.Text = '诊断中…'
        Set-CampusUiDiagnostic -Ui $script:ui -Phase Busy -Text '正在后台检查网络，请稍候。窗口可正常操作。'
        Set-CampusFeedback '网络诊断正在后台执行。'
    } catch {
        Set-CampusUiDiagnostic -Ui $script:ui -Text '无法启动网络诊断，请稍后重试。' -Success $false
        Set-CampusFeedback '无法启动网络诊断，请稍后重试。' -ErrorState
    }
}

function Stop-CampusUiDiagnostic {
    # Only the task created by this window may be cleaned up. Never search by name.
    $task = $script:diagnosticTask
    $script:diagnosticTask = $null
    if ($null -eq $task) { return }
    $process = $task.Process
    if ($null -ne $process) {
        try {
            if (-not $process.HasExited) {
                $process.Kill()
                [void]$process.WaitForExit(2000)
            }
        } catch { }
        finally { try { $process.Dispose() } catch { } }
    }
    try {
        $resultPath = [string]$task.ResultPath
        if (-not [string]::IsNullOrWhiteSpace($resultPath) -and [IO.File]::Exists($resultPath)) {
            [IO.File]::Delete($resultPath)
        }
    } catch { }
}

$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$guiRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\', '/').ToLowerInvariant()
$guiHasher = [Security.Cryptography.SHA256]::Create()
try { $guiKey = [BitConverter]::ToString($guiHasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($guiRoot))).Replace('-', '').Substring(0, 16) }
finally { $guiHasher.Dispose() }
$mutexName = 'Local\CampusNetworkTray_' + $sid + '_' + $guiKey
$showName = 'Local\CampusNetworkTrayShow_' + $sid + '_' + $guiKey
$created = $false
$guiMutex = New-Object Threading.Mutex($true, $mutexName, [ref]$created)
if (-not $created) {
    try {
        $showExisting = [Threading.EventWaitHandle]::OpenExisting($showName)
        try { [void]$showExisting.Set() } finally { $showExisting.Dispose() }
    } catch {
        [void][Windows.Forms.MessageBox]::Show('校园网助手正在启动，请稍候。', '校园网助手', 'OK', 'Information')
    } finally { $guiMutex.Dispose() }
    exit 0
}

$showEvent = $null
$script:ui = $null
$script:notify = $null
$timer = $null
$contextMenu = $null
$script:stateIcons = @{}
$script:diagnosticTask = $null
$script:iconState = ''
$script:allowExit = $false
$script:syncPreferences = $false
$script:currentModel = $null
$script:modelCache = @{}
$script:hideTipShown = $false

try {
    $showEvent = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::AutoReset, $showName)
    $script:ui = New-CampusTrayView
    foreach ($state in @('Online', 'LoggingIn', 'Error', 'Stopped')) { $script:stateIcons[$state] = New-CampusStateIcon $state }
    $script:notify = New-Object Windows.Forms.NotifyIcon
    $script:notify.Icon = $script:stateIcons.Stopped
    $script:notify.Text = '校园网助手'
    $script:notify.Visible = $true

    $contextMenu = New-Object Windows.Forms.ContextMenuStrip
    $menuOpen = $contextMenu.Items.Add('打开校园网助手')
    [void]$contextMenu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    $script:menuMonitor = $contextMenu.Items.Add('开始监测')
    $script:menuCheck = $contextMenu.Items.Add('立即检查')
    $menuAccount = $contextMenu.Items.Add('账号与设置')
    $menuDiagnostic = $contextMenu.Items.Add('网络诊断')
    $menuLogs = $contextMenu.Items.Add('运行日志')
    [void]$contextMenu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    $menuExit = $contextMenu.Items.Add('退出助手并停止监测')
    $script:notify.ContextMenuStrip = $contextMenu
    $menuOpen.add_Click({ Show-CampusWindow })
    $script:notify.add_DoubleClick({ Show-CampusWindow })
    $script:menuMonitor.add_Click({ Invoke-CampusMonitorToggle })
    $script:menuCheck.add_Click({ Invoke-CampusCheckNow })
    $menuAccount.add_Click({ Show-CampusWindow 'Account' })
    $menuDiagnostic.add_Click({ Start-CampusUiDiagnostic })
    $menuLogs.add_Click({ Show-CampusWindow 'Logs'; Update-CampusLogView })
    $menuExit.add_Click({
        try {
            [void](Stop-CampusMonitor -ProjectRoot $PSScriptRoot)
            $script:allowExit = $true
            $script:ui.Form.Close()
        } catch {
            Show-CampusWindow
            Set-CampusFeedback '无法停止后台监测，请稍后再退出。' -ErrorState
        }
    })

    foreach ($button in $script:ui.Navigation.Values) {
        $button.add_Click({
            param($sender, $eventArgs)
            Show-CampusUiPage $script:ui ([string]$sender.Tag)
            if ($sender.Tag -eq 'Logs') { Update-CampusLogView }
        })
    }
    $script:ui.ToggleMonitorButton.add_Click({ Invoke-CampusMonitorToggle })
    $script:ui.CheckNowButton.add_Click({ Invoke-CampusCheckNow })
    $script:ui.DiagnosisButton.add_Click({ Start-CampusUiDiagnostic })
    $script:ui.RefreshLogsButton.add_Click({ Update-CampusLogView })
    $script:ui.SaveButton.add_Click({
        $password = $null
        try {
            $carrier = @('campus', 'unicom', 'cmcc', 'telecom')[$script:ui.CarrierComboBox.SelectedIndex]
            $password = New-Object Security.SecureString
            foreach ($character in $script:ui.PasswordTextBox.Text.ToCharArray()) { $password.AppendChar($character) }
            $password.MakeReadOnly()
            Save-CampusUiCredential -ProjectRoot $PSScriptRoot -Account $script:ui.AccountTextBox.Text.Trim() -Carrier $carrier -Password $password
            $script:ui.PasswordTextBox.Clear()
            Set-CampusFeedback '账号已在本机加密保存。可在连接概览中开始监测。'
            Update-CampusTrayModel
        } catch {
            Set-CampusFeedback '保存失败：请检查账号。首次配置或更换账号、运营商时必须输入密码。' -ErrorState
        } finally {
            if ($null -ne $password) { $password.Dispose() }
        }
    })
    $script:ui.ClearCredentialButton.add_Click({
        $choice = [Windows.Forms.MessageBox]::Show($script:ui.Form, '清除本机保存的账号和密码，并停止自动监测？', '清除账号', 'YesNo', 'Question', 'Button2')
        if ($choice -ne [Windows.Forms.DialogResult]::Yes) { return }
        try {
            Clear-CampusUiCredential -ProjectRoot $PSScriptRoot
            $script:ui.AccountTextBox.Clear()
            $script:ui.PasswordTextBox.Clear()
            Set-CampusFeedback '已清除本机账号，并请求停止监测。'
            Update-CampusTrayModel
        } catch {
            Set-CampusFeedback '无法清除账号，请稍后重试。' -ErrorState
        }
    })
    $script:ui.StartupCheckBox.add_CheckedChanged({
        if ($script:syncPreferences) { return }
        try {
            Set-CampusStartup -ProjectRoot $PSScriptRoot -Enabled $script:ui.StartupCheckBox.Checked
            Set-CampusFeedback '开机启动设置已更新。'
        } catch {
            Set-CampusFeedback '无法更新开机启动设置，请稍后重试。' -ErrorState
            Update-CampusTrayModel
        }
    })
    $script:ui.MonitorOnLaunchCheckBox.add_CheckedChanged({
        if ($script:syncPreferences) { return }
        try {
            Set-CampusUiPreferences -ProjectRoot $PSScriptRoot -MonitorOnLaunch $script:ui.MonitorOnLaunchCheckBox.Checked
            Set-CampusFeedback '启动时自动监测设置已更新。'
        } catch {
            Set-CampusFeedback '无法保存设置，请稍后重试。' -ErrorState
            Update-CampusTrayModel
        }
    })
    $script:ui.Form.add_FormClosing({
        param($sender, $eventArgs)
        if ($eventArgs.CloseReason -eq [Windows.Forms.CloseReason]::UserClosing -and -not $script:allowExit) {
            $eventArgs.Cancel = $true
            $script:ui.Form.Hide()
            if (-not $script:hideTipShown) {
                $script:notify.ShowBalloonTip(2500, '校园网助手仍在运行', '双击托盘图标可打开；右键菜单可退出并停止监测。', [Windows.Forms.ToolTipIcon]::Info)
                $script:hideTipShown = $true
            }
        }
    })
    $script:ui.Form.add_Shown({
        if ($StartHidden -and $script:currentModel.CredentialAvailable) { $script:ui.Form.Hide() }
    })

    $startupMigrationFailed = $false
    try { [void](Update-CampusStartupIfNeeded -ProjectRoot $PSScriptRoot) }
    catch { $startupMigrationFailed = $true }
    Show-CampusUiPage $script:ui 'Status'
    Update-CampusTrayModel
    if ($null -ne $script:currentModel) {
        $script:ui.AccountTextBox.Text = [string]$script:currentModel.Account
        $carrierIndex = [Array]::IndexOf(@('campus', 'unicom', 'cmcc', 'telecom'), [string]$script:currentModel.Carrier)
        if ($carrierIndex -lt 0) { $carrierIndex = 1 }
        $script:ui.CarrierComboBox.SelectedIndex = $carrierIndex
        if (-not $script:currentModel.CredentialAvailable) {
            Show-CampusUiPage $script:ui 'Account'
            Set-CampusFeedback '欢迎使用。请先填写并保存校园网账号、运营商和密码。'
        } elseif ($script:currentModel.MonitorOnLaunch -and -not $script:currentModel.MonitorRunning) {
            try { [void](Start-CampusMonitor -ProjectRoot $PSScriptRoot); Update-CampusTrayModel } catch {
                Set-CampusFeedback '暂时无法启动自动监测，请检查账号设置后重试。' -ErrorState
            }
        }
    }
    if ($startupMigrationFailed) {
        Set-CampusFeedback '界面已打开，但原开机启动项未能更新。可在“账号与设置”中重新设置。' -ErrorState
    }

    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 1500
    $timer.add_Tick({
        try {
            if ($showEvent.WaitOne(0)) { Show-CampusWindow }
            Update-CampusTrayModel
            if ($null -ne $script:diagnosticTask) {
                try {
                    $result = Get-CampusDiagnosticResult -Task $script:diagnosticTask
                    if ($null -ne $result) {
                        Set-CampusUiDiagnostic -Ui $script:ui -Text ([string]$result.Text) -Success ([bool]$result.Success)
                        if ($result.Success) { Set-CampusFeedback '网络诊断完成。' } else { Set-CampusFeedback '网络诊断未完成，请查看诊断结果。' -ErrorState }
                        $script:diagnosticTask = $null
                        $script:ui.DiagnosisButton.Text = '开始诊断'
                        $script:ui.DiagnosisButton.Enabled = $true
                    }
                } catch {
                    Stop-CampusUiDiagnostic
                    $script:ui.DiagnosisButton.Text = '开始诊断'
                    $script:ui.DiagnosisButton.Enabled = $true
                    Set-CampusUiDiagnostic -Ui $script:ui -Text '无法读取诊断结果，请重新运行诊断。' -Success $false
                    Set-CampusFeedback '无法读取诊断结果，请重新运行诊断。' -ErrorState
                }
            }
        } catch {
            Set-CampusFeedback '暂时无法更新界面，后台监测仍按原设置运行。' -ErrorState
        }
    })
    $timer.Start()
    [Windows.Forms.Application]::Run($script:ui.Form)
} catch {
    [void][Windows.Forms.MessageBox]::Show('校园网助手无法启动。请确认项目文件完整，或使用原有命令入口。', '校园网助手', 'OK', 'Error')
} finally {
    if ($null -ne $timer) { $timer.Stop(); $timer.Dispose() }
    Stop-CampusUiDiagnostic
    if ($null -ne $script:notify) { $script:notify.Visible = $false; $script:notify.Dispose() }
    if ($null -ne $contextMenu) { $contextMenu.Dispose() }
    if ($null -ne $script:ui -and $null -ne $script:ui.Form) { $script:ui.Form.Dispose() }
    foreach ($icon in $script:stateIcons.Values) { $icon.Dispose() }
    if ($null -ne $showEvent) { $showEvent.Dispose() }
    try { $guiMutex.ReleaseMutex() } catch { }
    $guiMutex.Dispose()
}
