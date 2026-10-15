# Windows PowerShell 5.1; UI construction only. No network or credential access.
function ConvertTo-CampusColor([string]$Hex) {
    return [Drawing.ColorTranslator]::FromHtml($Hex)
}

function New-CampusUiLabel {
    param([string]$Text, [float]$Size = 10, [string]$Color = '#526174', [switch]$Bold)
    $label = New-Object Windows.Forms.Label
    $label.Text = $Text
    $label.AutoSize = $false
    $label.Dock = 'Fill'
    $label.Margin = New-Object Windows.Forms.Padding(0)
    $style = [Drawing.FontStyle]::Regular
    if ($Bold) { $style = [Drawing.FontStyle]::Bold }
    $label.Font = New-Object Drawing.Font('Microsoft YaHei UI', $Size, $style)
    $label.ForeColor = ConvertTo-CampusColor $Color
    $label.TextAlign = 'MiddleLeft'
    return $label
}

function New-CampusUiButton {
    param([string]$Text, [string]$Name, [switch]$Primary, [int]$Width = 132)
    $button = New-Object Windows.Forms.Button
    $button.Name = $Name
    $button.Text = $Text
    $button.Size = New-Object Drawing.Size($Width, 38)
    $button.Margin = New-Object Windows.Forms.Padding(0, 0, 12, 0)
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 1
    $button.FlatAppearance.BorderColor = ConvertTo-CampusColor '#D7E0EB'
    $button.BackColor = [Drawing.Color]::White
    $button.ForeColor = ConvertTo-CampusColor '#26384D'
    $button.Cursor = 'Hand'
    if ($Primary) {
        $button.BackColor = ConvertTo-CampusColor '#147D73'
        $button.ForeColor = [Drawing.Color]::White
        $button.FlatAppearance.BorderColor = $button.BackColor
    }
    return $button
}

function New-CampusUiCard {
    param([int]$Padding = 20)
    $panel = New-Object Windows.Forms.Panel
    $panel.Dock = 'Fill'
    $panel.BackColor = [Drawing.Color]::White
    $panel.Padding = New-Object Windows.Forms.Padding($Padding)
    $panel.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 16)
    return $panel
}

function New-CampusUiTable {
    param([int]$Rows, [int]$Columns = 1)
    $table = New-Object Windows.Forms.TableLayoutPanel
    $table.Dock = 'Fill'
    $table.RowCount = $Rows
    $table.ColumnCount = $Columns
    $table.Margin = New-Object Windows.Forms.Padding(0)
    $table.Padding = New-Object Windows.Forms.Padding(0)
    return $table
}

function Add-CampusUiRow([Windows.Forms.TableLayoutPanel]$Table, [float]$Height, [switch]$Percent) {
    $type = [Windows.Forms.SizeType]::Absolute
    if ($Percent) { $type = [Windows.Forms.SizeType]::Percent }
    [void]$Table.RowStyles.Add((New-Object Windows.Forms.RowStyle($type, $Height)))
}

function New-CampusTrayView {
    $ui = @{}
    $form = New-Object Windows.Forms.Form
    $form.Name = 'campusNetworkForm'
    $form.Text = '校园网助手'
    $form.ClientSize = New-Object Drawing.Size(1000, 716)
    $form.MinimumSize = New-Object Drawing.Size(920, 700)
    $form.StartPosition = 'CenterScreen'
    $form.AutoScaleMode = 'Dpi'
    $form.AutoScaleDimensions = New-Object Drawing.SizeF(96, 96)
    $form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9.5)
    $form.BackColor = ConvertTo-CampusColor '#F4F7FB'
    $ui.Form = $form

    $root = New-CampusUiTable -Rows 3
    Add-CampusUiRow $root 78
    Add-CampusUiRow $root 100 -Percent
    Add-CampusUiRow $root 38
    [void]$form.Controls.Add($root)

    $header = New-Object Windows.Forms.Panel
    $header.Dock = 'Fill'
    $header.BackColor = [Drawing.Color]::White
    $header.Margin = New-Object Windows.Forms.Padding(0)
    $header.Padding = New-Object Windows.Forms.Padding(26, 12, 26, 10)
    $heading = New-CampusUiTable -Rows 1 -Columns 2
    [void]$heading.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 60)))
    [void]$heading.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 40)))
    $brand = New-CampusUiLabel '校园网助手' 21 '#172E43' -Bold
    $tagline = New-CampusUiLabel '自动认证 · 连接状态 · 本机设置' 9.5 '#69798B'
    $tagline.TextAlign = 'MiddleRight'
    [void]$heading.Controls.Add($brand, 0, 0)
    [void]$heading.Controls.Add($tagline, 1, 0)
    [void]$header.Controls.Add($heading)
    [void]$root.Controls.Add($header, 0, 0)

    $body = New-CampusUiTable -Rows 1 -Columns 2
    [void]$body.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 184)))
    [void]$body.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
    [void]$root.Controls.Add($body, 0, 1)

    $nav = New-CampusUiTable -Rows 7
    $nav.Padding = New-Object Windows.Forms.Padding(18, 24, 12, 14)
    @(24, 48, 48, 48, 48) | ForEach-Object { Add-CampusUiRow $nav $_ }
    Add-CampusUiRow $nav 100 -Percent
    Add-CampusUiRow $nav 70
    $navTitle = New-CampusUiLabel '工作区' 8.5 '#7D8B9A'
    [void]$nav.Controls.Add($navTitle, 0, 0)
    $ui.Navigation = @{}
    $navItems = @(@('Status', '连接概览'), @('Account', '账号与设置'), @('Diagnostics', '网络诊断'), @('Logs', '运行日志'))
    $index = 1
    foreach ($item in $navItems) {
        $button = New-CampusUiButton $item[1] ('nav' + $item[0])
        $button.Dock = 'Fill'
        $button.Margin = New-Object Windows.Forms.Padding(0, 3, 0, 3)
        $button.TextAlign = 'MiddleLeft'
        $button.Padding = New-Object Windows.Forms.Padding(12, 0, 0, 0)
        $button.FlatAppearance.BorderSize = 0
        $button.BackColor = $form.BackColor
        $button.Tag = $item[0]
        [void]$nav.Controls.Add($button, 0, $index)
        $ui.Navigation[$item[0]] = $button
        $index++
    }
    $navNote = New-CampusUiLabel "关闭窗口后继续运行。`r`n右下角托盘可随时打开。" 8.5 '#758497'
    [void]$nav.Controls.Add($navNote, 0, 6)
    [void]$body.Controls.Add($nav, 0, 0)

    $content = New-Object Windows.Forms.Panel
    $content.Dock = 'Fill'
    $content.Padding = New-Object Windows.Forms.Padding(18, 22, 26, 10)
    $content.Margin = New-Object Windows.Forms.Padding(0)
    [void]$body.Controls.Add($content, 1, 0)
    $ui.Pages = @{}

    # Overview page. Flexible detail areas wrap instead of truncating diagnostics.
    $statusPage = New-CampusUiTable -Rows 5
    Add-CampusUiRow $statusPage 42
    Add-CampusUiRow $statusPage 52 -Percent
    Add-CampusUiRow $statusPage 30 -Percent
    Add-CampusUiRow $statusPage 54
    Add-CampusUiRow $statusPage 18 -Percent
    [void]$statusPage.Controls.Add((New-CampusUiLabel '连接概览' 17 '#172E43' -Bold), 0, 0)
    $connectionCard = New-CampusUiCard
    $connection = New-CampusUiTable -Rows 4
    Add-CampusUiRow $connection 42
    Add-CampusUiRow $connection 36
    Add-CampusUiRow $connection 100 -Percent
    Add-CampusUiRow $connection 27
    $ui.StatusTextLabel = New-CampusUiLabel '正在读取连接状态…' 21 '#147D73' -Bold
    $ui.StatusTextLabel.Name = 'statusTextLabel'
    $ui.MonitorStateLabel = New-CampusUiLabel '监测状态：正在初始化' 9.5 '#526174'
    $ui.MonitorStateLabel.Name = 'monitorStateLabel'
    $ui.DetailLabel = New-CampusUiLabel '启动后会自动读取校园网认证状态。' 10 '#526174'
    $ui.DetailLabel.Name = 'detailLabel'
    $ui.DetailLabel.TextAlign = 'TopLeft'
    $ui.VpnStateLabel = New-CampusUiLabel 'VPN 状态：正在读取' 9 '#758497'
    $ui.VpnStateLabel.Name = 'vpnStateLabel'
    [void]$connection.Controls.Add($ui.StatusTextLabel, 0, 0)
    [void]$connection.Controls.Add($ui.MonitorStateLabel, 0, 1)
    [void]$connection.Controls.Add($ui.DetailLabel, 0, 2)
    [void]$connection.Controls.Add($ui.VpnStateLabel, 0, 3)
    [void]$connectionCard.Controls.Add($connection)
    [void]$statusPage.Controls.Add($connectionCard, 0, 1)

    $historyCard = New-CampusUiCard -Padding 16
    $history = New-CampusUiTable -Rows 3 -Columns 2
    [void]$history.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 120)))
    [void]$history.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
    Add-CampusUiRow $history 30
    Add-CampusUiRow $history 100 -Percent
    Add-CampusUiRow $history 27
    [void]$history.Controls.Add((New-CampusUiLabel '最近自动登录' 9 '#758497'), 0, 0)
    [void]$history.Controls.Add((New-CampusUiLabel '最近异常' 9 '#758497'), 0, 1)
    [void]$history.Controls.Add((New-CampusUiLabel '状态更新时间' 9 '#758497'), 0, 2)
    $ui.LastLoginLabel = New-CampusUiLabel '暂无记录' 9 '#26384D'
    $ui.LastLoginLabel.Name = 'lastLoginLabel'
    $ui.LastErrorLabel = New-CampusUiLabel '暂无异常' 9 '#26384D'
    $ui.LastErrorLabel.Name = 'lastErrorLabel'
    $ui.UpdatedAtLabel = New-CampusUiLabel '—' 9 '#758497'
    [void]$history.Controls.Add($ui.LastLoginLabel, 1, 0)
    [void]$history.Controls.Add($ui.LastErrorLabel, 1, 1)
    [void]$history.Controls.Add($ui.UpdatedAtLabel, 1, 2)
    [void]$historyCard.Controls.Add($history)
    [void]$statusPage.Controls.Add($historyCard, 0, 2)
    $actions = New-Object Windows.Forms.FlowLayoutPanel
    $actions.Dock = 'Fill'
    $actions.Margin = New-Object Windows.Forms.Padding(0)
    $ui.ToggleMonitorButton = New-CampusUiButton '暂停监测' 'toggleMonitorButton' -Primary
    $ui.CheckNowButton = New-CampusUiButton '立即检查' 'checkNowButton'
    [void]$actions.Controls.Add($ui.ToggleMonitorButton)
    [void]$actions.Controls.Add($ui.CheckNowButton)
    [void]$statusPage.Controls.Add($actions, 0, 3)
    $ui.SuggestionLabel = New-CampusUiLabel '首次确认未登录后立即尝试认证，失败时按间隔重试。' 9 '#69798B'
    $ui.SuggestionLabel.Name = 'suggestionLabel'
    $ui.SuggestionLabel.TextAlign = 'TopLeft'
    [void]$statusPage.Controls.Add($ui.SuggestionLabel, 0, 4)
    $ui.Pages.Status = $statusPage

    # Account page. Password is never populated from saved credentials.
    $accountPage = New-CampusUiTable -Rows 4
    Add-CampusUiRow $accountPage 42
    Add-CampusUiRow $accountPage 308
    Add-CampusUiRow $accountPage 110
    Add-CampusUiRow $accountPage 100 -Percent
    [void]$accountPage.Controls.Add((New-CampusUiLabel '账号与设置' 17 '#172E43' -Bold), 0, 0)
    $accountCard = New-CampusUiCard
    $accountTable = New-CampusUiTable -Rows 6 -Columns 2
    [void]$accountTable.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 102)))
    [void]$accountTable.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
    @(46, 46, 46, 34, 46, 22) | ForEach-Object { Add-CampusUiRow $accountTable $_ }
    $ui.AccountTextBox = New-Object Windows.Forms.TextBox
    $ui.AccountTextBox.Name = 'accountTextBox'
    $ui.AccountTextBox.Dock = 'Top'
    $ui.AccountTextBox.MaxLength = 128
    $ui.AccountTextBox.Margin = New-Object Windows.Forms.Padding(0, 6, 0, 0)
    $ui.CarrierComboBox = New-Object Windows.Forms.ComboBox
    $ui.CarrierComboBox.Name = 'carrierComboBox'
    $ui.CarrierComboBox.DropDownStyle = 'DropDownList'
    $ui.CarrierComboBox.Dock = 'Top'
    $ui.CarrierComboBox.Margin = New-Object Windows.Forms.Padding(0, 6, 0, 0)
    [void]$ui.CarrierComboBox.Items.AddRange(@('校园网', '中国联通', '中国移动', '中国电信'))
    $ui.CarrierComboBox.SelectedIndex = 1
    $ui.PasswordTextBox = New-Object Windows.Forms.TextBox
    $ui.PasswordTextBox.Name = 'passwordTextBox'
    $ui.PasswordTextBox.UseSystemPasswordChar = $true
    $ui.PasswordTextBox.Dock = 'Top'
    $ui.PasswordTextBox.MaxLength = 256
    $ui.PasswordTextBox.Margin = New-Object Windows.Forms.Padding(0, 6, 0, 0)
    [void]$accountTable.Controls.Add((New-CampusUiLabel '校园网账号' 10 '#526174'), 0, 0)
    [void]$accountTable.Controls.Add((New-CampusUiLabel '运营商' 10 '#526174'), 0, 1)
    [void]$accountTable.Controls.Add((New-CampusUiLabel '密码' 10 '#526174'), 0, 2)
    [void]$accountTable.Controls.Add($ui.AccountTextBox, 1, 0)
    [void]$accountTable.Controls.Add($ui.CarrierComboBox, 1, 1)
    [void]$accountTable.Controls.Add($ui.PasswordTextBox, 1, 2)
    $passwordNote = New-CampusUiLabel '账号与运营商不变时，密码留空可保留原密码。' 8.5 '#758497'
    [void]$accountTable.Controls.Add($passwordNote, 1, 3)
    $saveActions = New-Object Windows.Forms.FlowLayoutPanel
    $saveActions.Dock = 'Fill'
    $saveActions.Margin = New-Object Windows.Forms.Padding(0, 4, 0, 0)
    $ui.SaveButton = New-CampusUiButton '保存账号' 'saveButton' -Primary -Width 118
    $ui.ClearCredentialButton = New-CampusUiButton '清除账号' 'clearCredentialButton' -Width 118
    [void]$saveActions.Controls.Add($ui.SaveButton)
    [void]$saveActions.Controls.Add($ui.ClearCredentialButton)
    [void]$accountTable.Controls.Add($saveActions, 1, 4)
    $ui.CredentialStateLabel = New-CampusUiLabel '账号密码仅保存在本机，密码由当前 Windows 用户加密。' 8.5 '#758497'
    [void]$accountTable.Controls.Add($ui.CredentialStateLabel, 0, 5)
    $accountTable.SetColumnSpan($ui.CredentialStateLabel, 2)
    [void]$accountCard.Controls.Add($accountTable)
    [void]$accountPage.Controls.Add($accountCard, 0, 1)
    $preferenceCard = New-CampusUiCard -Padding 16
    $preferences = New-CampusUiTable -Rows 2
    Add-CampusUiRow $preferences 34
    Add-CampusUiRow $preferences 34
    $ui.StartupCheckBox = New-Object Windows.Forms.CheckBox
    $ui.StartupCheckBox.Name = 'startupCheckBox'
    $ui.StartupCheckBox.Text = '登录 Windows 后在托盘启动'
    $ui.StartupCheckBox.Dock = 'Fill'
    $ui.StartupCheckBox.AutoSize = $true
    $ui.MonitorOnLaunchCheckBox = New-Object Windows.Forms.CheckBox
    $ui.MonitorOnLaunchCheckBox.Name = 'monitorOnLaunchCheckBox'
    $ui.MonitorOnLaunchCheckBox.Text = '打开助手时自动开始监测'
    $ui.MonitorOnLaunchCheckBox.Dock = 'Fill'
    $ui.MonitorOnLaunchCheckBox.AutoSize = $true
    [void]$preferences.Controls.Add($ui.StartupCheckBox, 0, 0)
    [void]$preferences.Controls.Add($ui.MonitorOnLaunchCheckBox, 0, 1)
    [void]$preferenceCard.Controls.Add($preferences)
    [void]$accountPage.Controls.Add($preferenceCard, 0, 2)
    $privacyNote = New-CampusUiLabel '更换账号或运营商时请重新输入密码。保存成功后，运行中的监测会使用新配置。' 9 '#69798B'
    $privacyNote.TextAlign = 'TopLeft'
    [void]$accountPage.Controls.Add($privacyNote, 0, 3)
    $ui.Pages.Account = $accountPage

    $diagnosticsPage = New-CampusUiTable -Rows 4
    Add-CampusUiRow $diagnosticsPage 42
    Add-CampusUiRow $diagnosticsPage 48
    Add-CampusUiRow $diagnosticsPage 52
    Add-CampusUiRow $diagnosticsPage 100 -Percent
    [void]$diagnosticsPage.Controls.Add((New-CampusUiLabel '网络诊断' 17 '#172E43' -Bold), 0, 0)
    [void]$diagnosticsPage.Controls.Add((New-CampusUiLabel '检查无线连接、校园网认证服务和 VPN 路由，给出对应处理建议。' 9.5 '#69798B'), 0, 1)
    $ui.DiagnosisButton = New-CampusUiButton '开始诊断' 'diagnosisButton' -Primary
    $ui.DiagnosisButton.Anchor = 'Top,Left'
    [void]$diagnosticsPage.Controls.Add($ui.DiagnosisButton, 0, 2)
    $ui.DiagnosticTextBox = New-Object Windows.Forms.RichTextBox
    $ui.DiagnosticTextBox.Name = 'diagnosticTextBox'
    $ui.DiagnosticTextBox.ReadOnly = $true
    $ui.DiagnosticTextBox.Dock = 'Fill'
    $ui.DiagnosticTextBox.BorderStyle = 'None'
    $ui.DiagnosticTextBox.BackColor = [Drawing.Color]::White
    $ui.DiagnosticTextBox.ForeColor = ConvertTo-CampusColor '#26384D'
    $ui.DiagnosticTextBox.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10)
    $ui.DiagnosticTextBox.DetectUrls = $false
    $ui.DiagnosticTextBox.Text = '点击“开始诊断”生成网络检查结果。' + "`r`n`r`n" + '诊断在后台执行，不影响窗口操作。'
    [void]$diagnosticsPage.Controls.Add($ui.DiagnosticTextBox, 0, 3)
    $ui.Pages.Diagnostics = $diagnosticsPage

    $logsPage = New-CampusUiTable -Rows 4
    Add-CampusUiRow $logsPage 42
    Add-CampusUiRow $logsPage 40
    Add-CampusUiRow $logsPage 52
    Add-CampusUiRow $logsPage 100 -Percent
    [void]$logsPage.Controls.Add((New-CampusUiLabel '运行日志' 17 '#172E43' -Bold), 0, 0)
    [void]$logsPage.Controls.Add((New-CampusUiLabel '显示最近 100 条记录。需要反馈问题时，可复制相关记录。' 9.5 '#69798B'), 0, 1)
    $ui.RefreshLogsButton = New-CampusUiButton '刷新日志' 'refreshLogsButton'
    $ui.RefreshLogsButton.Anchor = 'Top,Left'
    [void]$logsPage.Controls.Add($ui.RefreshLogsButton, 0, 2)
    $ui.LogTextBox = New-Object Windows.Forms.RichTextBox
    $ui.LogTextBox.Name = 'logTextBox'
    $ui.LogTextBox.ReadOnly = $true
    $ui.LogTextBox.Dock = 'Fill'
    $ui.LogTextBox.BorderStyle = 'None'
    $ui.LogTextBox.BackColor = [Drawing.Color]::White
    $ui.LogTextBox.ForeColor = ConvertTo-CampusColor '#26384D'
    $ui.LogTextBox.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9)
    $ui.LogTextBox.WordWrap = $false
    $ui.LogTextBox.DetectUrls = $false
    $ui.LogTextBox.Text = '暂无运行记录。'
    [void]$logsPage.Controls.Add($ui.LogTextBox, 0, 3)
    $ui.Pages.Logs = $logsPage

    foreach ($page in $ui.Pages.Values) {
        $page.Visible = $false
        [void]$content.Controls.Add($page)
    }
    $footer = New-Object Windows.Forms.Panel
    $footer.Dock = 'Fill'
    $footer.Padding = New-Object Windows.Forms.Padding(26, 0, 26, 0)
    $footer.Margin = New-Object Windows.Forms.Padding(0)
    $footer.BackColor = [Drawing.Color]::White
    $ui.FeedbackLabel = New-CampusUiLabel '就绪 · 密码仅保存在本机' 8.5 '#69798B'
    $ui.FeedbackLabel.Name = 'feedbackLabel'
    [void]$footer.Controls.Add($ui.FeedbackLabel)
    [void]$root.Controls.Add($footer, 0, 2)
    $ui.ActivePage = 'Status'
    return $ui
}

function Show-CampusUiPage {
    param([hashtable]$Ui, [ValidateSet('Status', 'Account', 'Diagnostics', 'Logs')][string]$Page)
    foreach ($entry in $Ui.Pages.GetEnumerator()) { $entry.Value.Visible = $entry.Key -eq $Page }
    foreach ($entry in $Ui.Navigation.GetEnumerator()) {
        if ($entry.Key -eq $Page) {
            $entry.Value.BackColor = ConvertTo-CampusColor '#DFEEE9'
            $entry.Value.ForeColor = ConvertTo-CampusColor '#116C63'
        } else {
            $entry.Value.BackColor = ConvertTo-CampusColor '#F4F7FB'
            $entry.Value.ForeColor = ConvertTo-CampusColor '#526174'
        }
    }
    $Ui.Pages[$Page].BringToFront()
    $Ui.ActivePage = $Page
}

function Format-CampusUiTime([string]$Value, [string]$Fallback = '暂无记录') {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Fallback }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($Value, [ref]$parsed)) {
        if ($parsed.Kind -eq [DateTimeKind]::Utc) { $parsed = $parsed.ToLocalTime() }
        return $parsed.ToString('yyyy-MM-dd HH:mm:ss')
    }
    return $Value
}

function Set-CampusUiModel {
    param([hashtable]$Ui, $Model)
    $Ui.StatusTextLabel.Text = [string]$Model.StatusText
    $Ui.DetailLabel.Text = [string]$Model.DetailText
    $Ui.LastLoginLabel.Text = Format-CampusUiTime ([string]$Model.LastLoginAt)
    $Ui.LastErrorLabel.Text = [string]$Model.LastError
    if ([string]::IsNullOrWhiteSpace($Ui.LastErrorLabel.Text)) { $Ui.LastErrorLabel.Text = '暂无异常' }
    $Ui.UpdatedAtLabel.Text = Format-CampusUiTime ([string]$Model.UpdatedAt) '—'
    $Ui.SuggestionLabel.Text = [string]$Model.Suggestion
    if ([string]::IsNullOrWhiteSpace($Ui.SuggestionLabel.Text)) { $Ui.SuggestionLabel.Text = '首次确认未登录后立即尝试认证，失败时按间隔重试。' }
    $color = '#BD7A18'
    $monitorText = '运行中'
    switch ([string]$Model.MonitorState) {
        'Starting' { $monitorText = '正在启动' }
        'LoggingIn' { $monitorText = '正在自动登录' }
        'RetryWaiting' { $monitorText = '等待重试' }
        'Error' { $monitorText = '需要检查' }
        'Stopped' { $monitorText = '已暂停' }
    }
    if ($Model.AuthState -eq 'Online') { $color = '#147D73' }
    if ($Model.MonitorState -eq 'LoggingIn') { $color = '#2875BD' }
    if ($Model.MonitorState -eq 'Error') { $color = '#BD7A18' }
    if (-not $Model.MonitorRunning -and $Model.MonitorState -ne 'Error') { $monitorText = '已暂停'; $color = '#758497' }
    $Ui.StatusTextLabel.ForeColor = ConvertTo-CampusColor $color
    $Ui.MonitorStateLabel.Text = '自动监测：' + $monitorText
    $Ui.ToggleMonitorButton.Text = '开始监测'
    if ($Model.MonitorRunning) { $Ui.ToggleMonitorButton.Text = '暂停监测' }
    $Ui.CheckNowButton.Enabled = [bool]$Model.MonitorRunning
    $Ui.VpnStateLabel.Text = 'VPN：未检测到活动隧道'
    if ($Model.VpnActive) { $Ui.VpnStateLabel.Text = 'VPN：已检测到活动隧道 · 校园网认证地址需直连' }
    $Ui.ClearCredentialButton.Enabled = [bool]$Model.CredentialAvailable
}
