# Windows PowerShell 5.1. UI construction only, with no credential or network access.
. (Join-Path $PSScriptRoot 'CampusNetwork.UiControls.ps1')
. (Join-Path $PSScriptRoot 'CampusNetwork.Presentation.ps1')

function ConvertTo-CampusColor([string]$Hex) { return [Drawing.ColorTranslator]::FromHtml($Hex) }

function New-CampusUiLabel {
    param([string]$Text, [float]$Size = 10.5, [string]$Color = '#636369', [switch]$Bold)
    $label = New-Object Windows.Forms.Label
    $label.Text = $Text; $label.AutoSize = $false; $label.Dock = 'Fill'
    $label.BackColor = [Drawing.Color]::Transparent
    $label.Margin = New-Object Windows.Forms.Padding(0)
    $style = if ($Bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }
    $label.Font = New-Object Drawing.Font('Microsoft YaHei UI', $Size, $style)
    $label.ForeColor = ConvertTo-CampusColor $Color; $label.TextAlign = 'MiddleLeft'
    return $label
}

function New-CampusUiButton {
    param([string]$Text, [string]$Name, [switch]$Primary, [int]$Width = 132, [switch]$Navigation)
    $button = New-Object Windows.Forms.Button
    $button.FlatStyle = 'Flat'; $button.UseVisualStyleBackColor = $false
    $button.FlatAppearance.BorderSize = if ($Navigation) { 0 } else { 1 }
    $button.FlatAppearance.BorderColor = ConvertTo-CampusColor '#D8D8DE'
    $button.FlatAppearance.MouseOverBackColor = ConvertTo-CampusColor '#EFF4FC'
    $button.FlatAppearance.MouseDownBackColor = ConvertTo-CampusColor '#DFEAF8'
    $button.Name = $Name; $button.Text = $Text
    $button.Size = New-Object Drawing.Size($Width, 40)
    $button.Margin = New-Object Windows.Forms.Padding(0, 0, 10, 0)
    $button.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10.5)
    $button.Cursor = 'Hand'
    $button.BackColor = [Drawing.Color]::White; $button.ForeColor = ConvertTo-CampusColor '#0065D4'
    if ($Primary) {
        $button.BackColor = ConvertTo-CampusColor '#007AFF'; $button.ForeColor = [Drawing.Color]::White
        $button.FlatAppearance.BorderColor = $button.BackColor
        $button.FlatAppearance.MouseOverBackColor = ConvertTo-CampusColor '#0070EB'
        $button.FlatAppearance.MouseDownBackColor = ConvertTo-CampusColor '#0064D1'
    }
    return $button
}

function New-CampusUiCard {
    param([int]$Padding = 24)
    $panel = New-Object CampusNetwork.UI.RoundedPanel
    $panel.Dock = 'Fill'; $panel.BackColor = [Drawing.Color]::White; $panel.Radius = 16
    $panel.BorderColor = ConvertTo-CampusColor '#E9E9EE'
    $panel.Padding = New-Object Windows.Forms.Padding($Padding)
    $panel.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 16)
    return $panel
}

function New-CampusUiTable {
    param([int]$Rows, [int]$Columns = 1)
    $table = New-Object Windows.Forms.TableLayoutPanel
    $table.Dock = 'Fill'; $table.RowCount = $Rows; $table.ColumnCount = $Columns
    $table.BackColor = [Drawing.Color]::Transparent
    $table.Margin = New-Object Windows.Forms.Padding(0); $table.Padding = New-Object Windows.Forms.Padding(0)
    if ($Rows -eq 1) { [void]$table.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 100))) }
    if ($Columns -eq 1) { [void]$table.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100))) }
    return $table
}

function Add-CampusUiRow([Windows.Forms.TableLayoutPanel]$Table, [float]$Height, [switch]$Percent) {
    $type = if ($Percent) { [Windows.Forms.SizeType]::Percent } else { [Windows.Forms.SizeType]::Absolute }
    [void]$Table.RowStyles.Add((New-Object Windows.Forms.RowStyle($type, $Height)))
}

function New-CampusGlyph([string]$Kind, [string]$Color = '#007AFF', [int]$Size = 24) {
    $glyph = New-Object CampusNetwork.UI.StatusGlyph
    $glyph.Kind = $Kind; $glyph.AccentColor = ConvertTo-CampusColor $Color
    $glyph.Size = New-Object Drawing.Size($Size, $Size); $glyph.Margin = New-Object Windows.Forms.Padding(0)
    return $glyph
}

function New-CampusPageHeading([string]$Title, [string]$Subtitle) {
    $heading = New-CampusUiTable -Rows 2
    Add-CampusUiRow $heading 40; Add-CampusUiRow $heading 28
    [void]$heading.Controls.Add((New-CampusUiLabel $Title 20 '#1C1C1E' -Bold), 0, 0)
    [void]$heading.Controls.Add((New-CampusUiLabel $Subtitle 10 '#636369'), 0, 1)
    $heading.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 10)
    return $heading
}

function New-CampusFieldWell($Control) {
    $well = New-Object CampusNetwork.UI.RoundedPanel
    $well.Dock = 'Fill'; $well.Radius = 10
    $well.BackColor = ConvertTo-CampusColor '#F3F3F7'; $well.BorderColor = $well.BackColor
    $well.Padding = New-Object Windows.Forms.Padding(12, 9, 12, 6)
    $well.Margin = New-Object Windows.Forms.Padding(0, 4, 0, 6)
    $Control.Dock = 'Fill'; $Control.Margin = New-Object Windows.Forms.Padding(0)
    $Control.BackColor = $well.BackColor; $Control.ForeColor = ConvertTo-CampusColor '#1C1C1E'
    $Control.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10.5)
    [void]$well.Controls.Add($Control)
    return $well
}

function New-CampusPreferenceRow([string]$Title, [string]$Note, $Toggle) {
    $row = New-CampusUiTable -Rows 2 -Columns 2
    [void]$row.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 24)))
    [void]$row.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
    Add-CampusUiRow $row 27; Add-CampusUiRow $row 23
    $Toggle.Dock = 'Fill'; $Toggle.Margin = New-Object Windows.Forms.Padding(0)
    $Toggle.AutoSize = $false; $Toggle.FlatStyle = 'Flat'
    $Toggle.ForeColor = ConvertTo-CampusColor '#007AFF'
    $Toggle.BackColor = [Drawing.Color]::White
    $Toggle.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10.5)
    $Toggle.FlatAppearance.CheckedBackColor = ConvertTo-CampusColor '#EAF2FF'
    $Toggle.FlatAppearance.MouseOverBackColor = ConvertTo-CampusColor '#F4F7FC'
    $Toggle.FlatAppearance.MouseDownBackColor = ConvertTo-CampusColor '#EAF2FF'
    $Toggle.AccessibleName = $Title; $Toggle.Text = ''
    $titleLabel = New-CampusUiLabel $Title 10.5 '#1C1C1E'; $titleLabel.Cursor = 'Hand'
    $titleLabel.add_Click({ if ($Toggle.Enabled) { [void]$Toggle.Focus(); $Toggle.Checked = -not $Toggle.Checked } }.GetNewClosure())
    $description = New-CampusUiLabel $Note 9.5 '#636369'
    [void]$row.Controls.Add($Toggle, 0, 0); [void]$row.Controls.Add($titleLabel, 1, 0)
    [void]$row.Controls.Add($description, 1, 1)
    return $row
}

function New-CampusUiSeparator {
    $line = New-Object Windows.Forms.Panel
    $line.Dock = 'Top'; $line.Height = 1; $line.BackColor = ConvertTo-CampusColor '#E9E9EE'
    $line.Margin = New-Object Windows.Forms.Padding(0)
    return $line
}

function New-CampusTrayView {
    $ui = @{}
    $form = New-Object Windows.Forms.Form
    $form.Name = 'campusNetworkForm'; $form.Text = '校园网助手'
    $form.ClientSize = New-Object Drawing.Size(1040, 760); $form.MinimumSize = New-Object Drawing.Size(960, 720)
    $form.StartPosition = 'CenterScreen'; $form.AutoScaleMode = 'Dpi'
    $form.AutoScaleDimensions = New-Object Drawing.SizeF(96, 96)
    $form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9.5)
    $form.BackColor = ConvertTo-CampusColor '#F2F2F7'; $ui.Form = $form
    $ui.ToolTips = New-Object Windows.Forms.ToolTip
    $ui.ToolTips.AutoPopDelay = 15000
    $hintProvider = $ui.ToolTips
    $form.add_Disposed({ $hintProvider.Dispose() }.GetNewClosure())
    $root = New-CampusUiTable -Rows 2
    Add-CampusUiRow $root 100 -Percent; Add-CampusUiRow $root 32
    [void]$form.Controls.Add($root)
    $body = New-CampusUiTable -Rows 1 -Columns 2
    [void]$body.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 216)))
    [void]$body.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
    [void]$root.Controls.Add($body, 0, 0)

    $nav = New-CampusUiTable -Rows 8
    $nav.BackColor = ConvertTo-CampusColor '#F7F7FA'; $nav.Padding = New-Object Windows.Forms.Padding(18, 28, 18, 20)
    @(96, 28, 54, 54, 54, 54) | ForEach-Object { Add-CampusUiRow $nav $_ }
    Add-CampusUiRow $nav 100 -Percent; Add-CampusUiRow $nav 92
    $brand = New-CampusUiTable -Rows 1 -Columns 2
    [void]$brand.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 48)))
    [void]$brand.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
    $brandIcon = New-Object CampusNetwork.UI.RoundedPanel
    $brandIcon.Size = New-Object Drawing.Size(40, 40); $brandIcon.Radius = 12
    $brandIcon.BackColor = ConvertTo-CampusColor '#007AFF'; $brandIcon.BorderColor = $brandIcon.BackColor
    $brandIcon.Padding = New-Object Windows.Forms.Padding(8); $brandIcon.Margin = New-Object Windows.Forms.Padding(0, 9, 0, 0)
    $wifi = New-CampusGlyph 'Wifi' '#FFFFFF'; $wifi.Dock = 'Fill'; [void]$brandIcon.Controls.Add($wifi)
    $brandCopy = New-CampusUiTable -Rows 2
    $brandCopy.Dock = 'Top'; $brandCopy.Height = 62
    Add-CampusUiRow $brandCopy 34; Add-CampusUiRow $brandCopy 26
    [void]$brandCopy.Controls.Add((New-CampusUiLabel '校园网助手' 14 '#1C1C1E' -Bold), 0, 0)
    [void]$brandCopy.Controls.Add((New-CampusUiLabel '让连接更轻松' 9 '#636369'), 0, 1)
    [void]$brand.Controls.Add($brandIcon, 0, 0); [void]$brand.Controls.Add($brandCopy, 1, 0)
    [void]$nav.Controls.Add($brand, 0, 0)
    $navTitle = New-CampusUiLabel '校园网络' 9 '#636369'; $navTitle.Padding = New-Object Windows.Forms.Padding(12, 0, 0, 0)
    [void]$nav.Controls.Add($navTitle, 0, 1)
    $ui.Navigation = @{}; $ui.NavigationGlyphs = @{}
    $navItems = @(@('Status', '连接概览', 'Wifi'), @('Account', '账号与设置', 'Settings'), @('Diagnostics', '网络诊断', 'Diagnostics'), @('Logs', '运行日志', 'Logs'))
    $index = 2
    foreach ($item in $navItems) {
        $button = New-CampusUiButton $item[1] ('nav' + $item[0]) -Navigation; $button.Dock = 'Fill'
        $button.Margin = New-Object Windows.Forms.Padding(0, 4, 0, 4); $button.TextAlign = 'MiddleLeft'
        $button.Padding = New-Object Windows.Forms.Padding(42, 0, 0, 0)
        $button.BackColor = $nav.BackColor; $button.ForeColor = ConvertTo-CampusColor '#636369'; $button.Tag = $item[0]
        $glyph = New-CampusGlyph $item[2] '#7C7C82' 20; $glyph.Location = New-Object Drawing.Point(14, 13)
        $glyph.add_Click({ param($sender, $eventArgs) $sender.Parent.PerformClick() })
        [void]$button.Controls.Add($glyph); [void]$nav.Controls.Add($button, 0, $index)
        $ui.Navigation[$item[0]] = $button; $ui.NavigationGlyphs[$item[0]] = $glyph; $index++
    }
    $navFoot = New-CampusUiTable -Rows 3
    Add-CampusUiRow $navFoot 30; Add-CampusUiRow $navFoot 24; Add-CampusUiRow $navFoot 38
    [void]$navFoot.Controls.Add((New-CampusGlyph 'Shield' '#8E8E93' 20), 0, 0)
    [void]$navFoot.Controls.Add((New-CampusUiLabel '凭据只保存在本机' 9.5 '#636369'), 0, 1)
    [void]$navFoot.Controls.Add((New-CampusUiLabel "关闭窗口后继续运行。`r`n双击托盘图标返回。" 9 '#636369'), 0, 2)
    [void]$nav.Controls.Add($navFoot, 0, 7); [void]$body.Controls.Add($nav, 0, 0)
    $content = New-Object Windows.Forms.Panel
    $content.Dock = 'Fill'; $content.Margin = New-Object Windows.Forms.Padding(0)
    $content.Padding = New-Object Windows.Forms.Padding(30, 24, 30, 12)
    [void]$body.Controls.Add($content, 1, 0); $ui.Pages = @{}

    $statusPage = New-CampusUiTable -Rows 5
    Add-CampusUiRow $statusPage 80; Add-CampusUiRow $statusPage 272
    Add-CampusUiRow $statusPage 172; Add-CampusUiRow $statusPage 88; Add-CampusUiRow $statusPage 100 -Percent
    [void]$statusPage.Controls.Add((New-CampusPageHeading '连接概览' '查看认证状态与自动监测情况。'), 0, 0)
    $connectionCard = New-CampusUiCard
    $connection = New-CampusUiTable -Rows 4
    Add-CampusUiRow $connection 64; Add-CampusUiRow $connection 54; Add-CampusUiRow $connection 34; Add-CampusUiRow $connection 56
    $headline = New-CampusUiTable -Rows 1 -Columns 2
    [void]$headline.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 76)))
    [void]$headline.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
    $ui.StatusIconWell = New-Object CampusNetwork.UI.RoundedPanel
    $ui.StatusIconWell.Size = New-Object Drawing.Size(58, 58); $ui.StatusIconWell.Radius = 18
    $ui.StatusIconWell.BackColor = ConvertTo-CampusColor '#EAF8EE'; $ui.StatusIconWell.BorderColor = $ui.StatusIconWell.BackColor
    $ui.StatusIconWell.Padding = New-Object Windows.Forms.Padding(14); $ui.StatusIconWell.Margin = New-Object Windows.Forms.Padding(0, 4, 0, 0)
    $ui.StatusGlyph = New-CampusGlyph 'Online' '#28A745' 30; $ui.StatusGlyph.Dock = 'Fill'
    [void]$ui.StatusIconWell.Controls.Add($ui.StatusGlyph)
    $statusCopy = New-CampusUiTable -Rows 2
    Add-CampusUiRow $statusCopy 38; Add-CampusUiRow $statusCopy 26
    $ui.StatusTextLabel = New-CampusUiLabel '正在读取连接状态' 22 '#1C1C1E' -Bold; $ui.StatusTextLabel.Name = 'statusTextLabel'
    $ui.MonitorStateLabel = New-CampusUiLabel '自动监测：正在初始化' 10 '#636369'; $ui.MonitorStateLabel.Name = 'monitorStateLabel'
    [void]$statusCopy.Controls.Add($ui.StatusTextLabel, 0, 0); [void]$statusCopy.Controls.Add($ui.MonitorStateLabel, 0, 1)
    $ui.StatusBadge = New-Object CampusNetwork.UI.RoundedPanel
    $ui.StatusBadge.Size = New-Object Drawing.Size(88, 28); $ui.StatusBadge.Radius = 14; $ui.StatusBadge.Anchor = 'Top,Right'
    $ui.StatusBadge.Padding = New-Object Windows.Forms.Padding(8, 2, 8, 2); $ui.StatusBadge.Margin = New-Object Windows.Forms.Padding(0, 10, 0, 0)
    $ui.BadgeLabel = New-CampusUiLabel '检查中' 8.5 '#6C6C70'; $ui.BadgeLabel.TextAlign = 'MiddleCenter'
    [void]$ui.StatusBadge.Controls.Add($ui.BadgeLabel)
    # Retain the view keys for compatibility while presenting the state once.
    $ui.StatusBadge.Visible = $false; [void]$connectionCard.Controls.Add($ui.StatusBadge)
    [void]$headline.Controls.Add($ui.StatusIconWell, 0, 0); [void]$headline.Controls.Add($statusCopy, 1, 0)
    $ui.DetailLabel = New-CampusUiLabel '启动后会自动读取校园网认证状态。' 10.5 '#48484A'; $ui.DetailLabel.Name = 'detailLabel'
    $ui.DetailLabel.AutoEllipsis = $true
    $ui.DetailLabel.TextAlign = 'TopLeft'; $ui.DetailLabel.Padding = New-Object Windows.Forms.Padding(0, 8, 0, 0)
    $vpnWell = New-Object CampusNetwork.UI.RoundedPanel
    $vpnWell.Dock = 'Fill'; $vpnWell.Radius = 10; $vpnWell.Margin = New-Object Windows.Forms.Padding(0)
    $vpnWell.BackColor = ConvertTo-CampusColor '#F5F5F8'; $vpnWell.BorderColor = $vpnWell.BackColor
    $vpnWell.Padding = New-Object Windows.Forms.Padding(12, 0, 12, 0)
    $ui.VpnStateLabel = New-CampusUiLabel 'VPN 状态：正在读取' 9.5 '#636369'; $ui.VpnStateLabel.Name = 'vpnStateLabel'
    [void]$vpnWell.Controls.Add($ui.VpnStateLabel)
    [void]$connection.Controls.Add($headline, 0, 0); [void]$connection.Controls.Add($ui.DetailLabel, 0, 1); [void]$connection.Controls.Add($vpnWell, 0, 2)
    [void]$connectionCard.Controls.Add($connection); [void]$statusPage.Controls.Add($connectionCard, 0, 1)
    $historyCard = New-CampusUiCard -Padding 20
    $history = New-CampusUiTable -Rows 3 -Columns 2
    [void]$history.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 124)))
    [void]$history.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
    Add-CampusUiRow $history 32; Add-CampusUiRow $history 52; Add-CampusUiRow $history 32
    [void]$history.Controls.Add((New-CampusUiLabel '最近自动登录' 10 '#636369'), 0, 0)
    [void]$history.Controls.Add((New-CampusUiLabel '最近异常' 10 '#636369'), 0, 1)
    [void]$history.Controls.Add((New-CampusUiLabel '状态更新' 10 '#636369'), 0, 2)
    $ui.LastLoginLabel = New-CampusUiLabel '暂无记录' 10.5 '#3A3A3C'; $ui.LastLoginLabel.Name = 'lastLoginLabel'
    $ui.LastErrorLabel = New-CampusUiLabel '暂无异常' 10 '#3A3A3C'; $ui.LastErrorLabel.Name = 'lastErrorLabel'
    $ui.LastErrorLabel.AutoEllipsis = $true
    $ui.UpdatedAtLabel = New-CampusUiLabel '—' 10 '#636369'
    [void]$history.Controls.Add($ui.LastLoginLabel, 1, 0); [void]$history.Controls.Add($ui.LastErrorLabel, 1, 1); [void]$history.Controls.Add($ui.UpdatedAtLabel, 1, 2)
    [void]$historyCard.Controls.Add($history); [void]$statusPage.Controls.Add($historyCard, 0, 2)
    $actions = New-Object Windows.Forms.FlowLayoutPanel
    $actions.Dock = 'Fill'; $actions.Margin = New-Object Windows.Forms.Padding(0, 12, 0, 0)
    $ui.ToggleMonitorButton = New-CampusUiButton '暂停监测' 'toggleMonitorButton' -Primary
    $ui.CheckNowButton = New-CampusUiButton '立即检查' 'checkNowButton'
    [void]$actions.Controls.Add($ui.ToggleMonitorButton); [void]$actions.Controls.Add($ui.CheckNowButton)
    [void]$connection.Controls.Add($actions, 0, 3)
    $ui.SuggestionLabel = New-CampusUiLabel '首次确认未登录后立即尝试认证，失败时按间隔重试。' 10 '#636369'
    $ui.SuggestionLabel.Name = 'suggestionLabel'; $ui.SuggestionLabel.TextAlign = 'TopLeft'
    $ui.SuggestionLabel.AutoEllipsis = $true
    $ui.SuggestionLabel.Padding = New-Object Windows.Forms.Padding(2, 2, 2, 0)
    [void]$statusPage.Controls.Add($ui.SuggestionLabel, 0, 3); $ui.Pages.Status = $statusPage

    $accountPage = New-CampusUiTable -Rows 5
    Add-CampusUiRow $accountPage 80; Add-CampusUiRow $accountPage 340; Add-CampusUiRow $accountPage 28
    Add-CampusUiRow $accountPage 160; Add-CampusUiRow $accountPage 100 -Percent
    [void]$accountPage.Controls.Add((New-CampusPageHeading '账号与设置' '管理本机账号与自动监测偏好。'), 0, 0)
    $accountCard = New-CampusUiCard
    $accountTable = New-CampusUiTable -Rows 6 -Columns 2
    [void]$accountTable.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 100)))
    [void]$accountTable.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
    @(54, 54, 54, 42, 48, 24) | ForEach-Object { Add-CampusUiRow $accountTable $_ }
    $ui.AccountTextBox = New-Object Windows.Forms.TextBox
    $ui.AccountTextBox.Name = 'accountTextBox'; $ui.AccountTextBox.MaxLength = 128; $ui.AccountTextBox.BorderStyle = 'None'; $ui.AccountTextBox.AccessibleName = '校园网账号'
    $ui.CarrierComboBox = New-Object CampusNetwork.UI.RoundedComboBox
    $ui.CarrierComboBox.Name = 'carrierComboBox'; $ui.CarrierComboBox.DropDownStyle = 'DropDownList'; $ui.CarrierComboBox.FlatStyle = 'Flat'; $ui.CarrierComboBox.AccessibleName = '运营商'
    [void]$ui.CarrierComboBox.Items.AddRange(@('校园网', '中国联通', '中国移动', '中国电信')); $ui.CarrierComboBox.SelectedIndex = 1
    $ui.PasswordTextBox = New-Object Windows.Forms.TextBox
    $ui.PasswordTextBox.Name = 'passwordTextBox'; $ui.PasswordTextBox.UseSystemPasswordChar = $true
    $ui.PasswordTextBox.MaxLength = 256; $ui.PasswordTextBox.BorderStyle = 'None'; $ui.PasswordTextBox.AccessibleName = '校园网密码'
    [void]$accountTable.Controls.Add((New-CampusUiLabel '校园网账号' 10 '#3A3A3C'), 0, 0)
    [void]$accountTable.Controls.Add((New-CampusUiLabel '运营商' 10 '#3A3A3C'), 0, 1)
    [void]$accountTable.Controls.Add((New-CampusUiLabel '密码' 10 '#3A3A3C'), 0, 2)
    [void]$accountTable.Controls.Add((New-CampusFieldWell $ui.AccountTextBox), 1, 0)
    [void]$accountTable.Controls.Add((New-CampusFieldWell $ui.CarrierComboBox), 1, 1)
    [void]$accountTable.Controls.Add((New-CampusFieldWell $ui.PasswordTextBox), 1, 2)
    $passwordHint = New-CampusUiLabel "账号与运营商不变时，留空保留原密码。`r`n更换账号或运营商时，请输入新密码。" 9.5 '#636369'
    $passwordHint.Name = 'passwordHintLabel'; $passwordHint.TextAlign = 'TopLeft'
    $passwordHint.Padding = New-Object Windows.Forms.Padding(0, 3, 0, 0)
    [void]$accountTable.Controls.Add($passwordHint, 1, 3)
    $saveActions = New-Object Windows.Forms.FlowLayoutPanel
    $saveActions.Dock = 'Fill'; $saveActions.Margin = New-Object Windows.Forms.Padding(0, 4, 0, 0)
    $ui.SaveButton = New-CampusUiButton '保存账号' 'saveButton' -Primary -Width 118
    $ui.ClearCredentialButton = New-CampusUiButton '清除账号' 'clearCredentialButton' -Width 118
    $ui.ClearCredentialButton.BackColor = [Drawing.Color]::White; $ui.ClearCredentialButton.ForeColor = ConvertTo-CampusColor '#B42318'
    $ui.ClearCredentialButton.FlatAppearance.BorderSize = 0
    $ui.ClearCredentialButton.FlatAppearance.MouseOverBackColor = ConvertTo-CampusColor '#FFE4E2'
    $ui.ClearCredentialButton.FlatAppearance.MouseDownBackColor = ConvertTo-CampusColor '#FFD5D1'
    [void]$saveActions.Controls.Add($ui.SaveButton); [void]$saveActions.Controls.Add($ui.ClearCredentialButton)
    [void]$accountTable.Controls.Add($saveActions, 1, 4)
    $ui.CredentialStateLabel = New-CampusUiLabel '密码已加密，只保存在这台电脑。' 9.5 '#636369'
    [void]$accountTable.Controls.Add($ui.CredentialStateLabel, 1, 5)
    [void]$accountCard.Controls.Add($accountTable)
    [void]$accountPage.Controls.Add($accountCard, 0, 1)
    [void]$accountPage.Controls.Add((New-CampusUiLabel '自动化' 10 '#636369'), 0, 2)
    $preferenceCard = New-CampusUiCard -Padding 20
    $preferences = New-CampusUiTable -Rows 3
    Add-CampusUiRow $preferences 50; Add-CampusUiRow $preferences 4; Add-CampusUiRow $preferences 50
    $ui.StartupCheckBox = New-Object Windows.Forms.CheckBox; $ui.StartupCheckBox.Name = 'startupCheckBox'
    $ui.MonitorOnLaunchCheckBox = New-Object Windows.Forms.CheckBox; $ui.MonitorOnLaunchCheckBox.Name = 'monitorOnLaunchCheckBox'
    [void]$preferences.Controls.Add((New-CampusPreferenceRow '登录 Windows 后启动' '在托盘中安静运行，随时查看连接状态。' $ui.StartupCheckBox), 0, 0)
    [void]$preferences.Controls.Add((New-CampusUiSeparator), 0, 1)
    [void]$preferences.Controls.Add((New-CampusPreferenceRow '打开助手时自动监测' '暂停后会记住你的选择，可随时手动开启。' $ui.MonitorOnLaunchCheckBox), 0, 2)
    [void]$preferenceCard.Controls.Add($preferences); [void]$accountPage.Controls.Add($preferenceCard, 0, 3)
    $ui.Pages.Account = $accountPage

    foreach ($definition in @(@('Diagnostics', '网络诊断', '查看检查结论与处理建议。'), @('Logs', '运行日志', '查看最近的认证与监测记录。'))) {
        $page = New-CampusUiTable -Rows 3
        Add-CampusUiRow $page 80; Add-CampusUiRow $page 64; Add-CampusUiRow $page 100 -Percent
        [void]$page.Controls.Add((New-CampusPageHeading $definition[1] $definition[2]), 0, 0)
        $toolbar = New-CampusUiTable -Rows 1 -Columns 2
        [void]$toolbar.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
        [void]$toolbar.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 142)))
        if ($definition[0] -eq 'Diagnostics') {
            $copy = "检查校园网认证、VPN 与服务端口。`r`n诊断在后台执行，你可以继续操作。"
            $ui.DiagnosisButton = New-CampusUiButton '开始诊断' 'diagnosisButton' -Primary; $button = $ui.DiagnosisButton
        } else {
            $copy = "最近 100 条运行记录。`r`n选中相关文字即可复制。"
            $ui.RefreshLogsButton = New-CampusUiButton '刷新日志' 'refreshLogsButton'; $button = $ui.RefreshLogsButton
        }
        $description = New-CampusUiLabel $copy 10 '#636369'; $description.TextAlign = 'TopLeft'
        $description.Padding = New-Object Windows.Forms.Padding(0, 6, 0, 0)
        $button.Anchor = 'Top,Right'; $button.Margin = New-Object Windows.Forms.Padding(0, 5, 0, 0)
        [void]$toolbar.Controls.Add($description, 0, 0); [void]$toolbar.Controls.Add($button, 1, 0)
        [void]$page.Controls.Add($toolbar, 0, 1)
        $resultCard = New-CampusUiCard -Padding 20
        $textBox = New-Object Windows.Forms.RichTextBox
        $textBox.ReadOnly = $true; $textBox.Dock = 'Fill'; $textBox.BorderStyle = 'None'
        $textBox.BackColor = [Drawing.Color]::White; $textBox.ForeColor = ConvertTo-CampusColor '#48484A'
        $textBox.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9.5); $textBox.DetectUrls = $false
        $textBox.Margin = New-Object Windows.Forms.Padding(0, 6, 0, 0)
        if ($definition[0] -eq 'Diagnostics') {
            $textBox.Name = 'diagnosticTextBox'; $ui.DiagnosticTextBox = $textBox
            $resultLayout = New-CampusUiTable -Rows 6
            Add-CampusUiRow $resultLayout 32; Add-CampusUiRow $resultLayout 32
            Add-CampusUiRow $resultLayout 128; Add-CampusUiRow $resultLayout 66
            Add-CampusUiRow $resultLayout 28; Add-CampusUiRow $resultLayout 100 -Percent
            $ui.DiagnosticTitleLabel = New-CampusUiLabel '' 16 '#1C1C1E' -Bold
            $ui.DiagnosticSummaryLabel = New-CampusUiLabel '' 10 '#636369'; $ui.DiagnosticSummaryLabel.AutoEllipsis = $true
            [void]$resultLayout.Controls.Add($ui.DiagnosticTitleLabel, 0, 0)
            [void]$resultLayout.Controls.Add($ui.DiagnosticSummaryLabel, 0, 1)
            $checks = New-CampusUiTable -Rows 4 -Columns 3
            [void]$checks.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 60)))
            [void]$checks.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 28)))
            [void]$checks.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 40)))
            $ui.DiagnosticRows = @()
            for ($index = 0; $index -lt 4; $index++) {
                Add-CampusUiRow $checks 32
                $label = New-CampusUiLabel '' 10 '#3A3A3C'
                $glyph = New-CampusGlyph 'Info' '#636369' 18; $glyph.Anchor = 'Left'
                $value = New-CampusUiLabel '' 10 '#636369'; $value.AutoEllipsis = $true
                [void]$checks.Controls.Add($label, 0, $index); [void]$checks.Controls.Add($glyph, 1, $index); [void]$checks.Controls.Add($value, 2, $index)
                $ui.DiagnosticRows += @{ Label = $label; Glyph = $glyph; Value = $value }
            }
            [void]$resultLayout.Controls.Add($checks, 0, 2)
            $ui.DiagnosticAdviceLabel = New-CampusUiLabel '' 10 '#48484A'
            $ui.DiagnosticAdviceLabel.AutoEllipsis = $true; $ui.DiagnosticAdviceLabel.Padding = New-Object Windows.Forms.Padding(0, 8, 0, 6)
            [void]$resultLayout.Controls.Add($ui.DiagnosticAdviceLabel, 0, 3)
            [void]$resultLayout.Controls.Add((New-CampusUiLabel '完整结果 · 可选中复制' 9.5 '#636369'), 0, 4)
            [void]$resultLayout.Controls.Add($textBox, 0, 5)
        } else {
            $textBox.Name = 'logTextBox'; $textBox.WordWrap = $false; $textBox.Text = '暂无运行记录。'; $ui.LogTextBox = $textBox
            $textBox.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10.5)
            $resultLayout = New-CampusUiTable -Rows 2
            Add-CampusUiRow $resultLayout 32; Add-CampusUiRow $resultLayout 100 -Percent
            [void]$resultLayout.Controls.Add((New-CampusUiLabel '最近记录' 12 '#1C1C1E' -Bold), 0, 0)
            [void]$resultLayout.Controls.Add($textBox, 0, 1)
        }
        [void]$resultCard.Controls.Add($resultLayout)
        [void]$page.Controls.Add($resultCard, 0, 2); $ui.Pages[$definition[0]] = $page
    }
    foreach ($page in $ui.Pages.Values) { $page.Visible = $false; [void]$content.Controls.Add($page) }
    $footer = New-Object Windows.Forms.Panel
    $footer.Dock = 'Fill'; $footer.Margin = New-Object Windows.Forms.Padding(0)
    $footer.BackColor = ConvertTo-CampusColor '#F2F2F7'; $footer.Padding = New-Object Windows.Forms.Padding(246, 0, 30, 0)
    $ui.FeedbackLabel = New-CampusUiLabel '就绪 · 密码仅保存在本机' 9 '#636369'; $ui.FeedbackLabel.Name = 'feedbackLabel'
    [void]$footer.Controls.Add($ui.FeedbackLabel); [void]$root.Controls.Add($footer, 0, 1)
    $ui.ActivePage = 'Status'
    Set-CampusUiDiagnostic -Ui $ui -Text '' -Phase Idle
    return $ui
}

function Set-CampusUiDiagnostic {
    param([hashtable]$Ui, [AllowEmptyString()][string]$Text = '', [bool]$Success = $false,
        [ValidateSet('Idle', 'Busy', 'Complete')][string]$Phase = 'Complete')
    $presentation = ConvertTo-CampusDiagnosticPresentation -Text $Text -Success $Success
    if ($Phase -ne 'Complete') {
        $presentation.Title = if ($Phase -eq 'Busy') { '正在检查连接' } else { '等待开始诊断' }
        $presentation.Summary = if ($Phase -eq 'Busy') { '检查在后台执行，可继续使用其他页面。' } else { '点击开始诊断，查看认证与端口状态。' }
        $presentation.Tone = 'Neutral'; $presentation.Advice = '诊断只检查连接，不会提交账号密码。'
        foreach ($item in $presentation.Items) { $item.Value = if ($Phase -eq 'Busy') { '检查中' } else { '未检查' }; $item.Tone = 'Neutral' }
    }
    $Ui.DiagnosticTitleLabel.Text = $presentation.Title
    $Ui.DiagnosticSummaryLabel.Text = $presentation.Summary
    $Ui.DiagnosticAdviceLabel.Text = '建议：' + $presentation.Advice
    $Ui.ToolTips.SetToolTip($Ui.DiagnosticSummaryLabel, $presentation.Summary)
    $Ui.ToolTips.SetToolTip($Ui.DiagnosticAdviceLabel, $Ui.DiagnosticAdviceLabel.Text)
    for ($index = 0; $index -lt $Ui.DiagnosticRows.Count; $index++) {
        $item = $presentation.Items[$index]; $row = $Ui.DiagnosticRows[$index]
        $color = '#636369'; $kind = 'Info'
        if ($item.Tone -eq 'Success') { $color = '#248A3D'; $kind = 'Online' }
        elseif ($item.Tone -eq 'Warning') { $color = '#A05A00'; $kind = 'Warning' }
        elseif ($Phase -eq 'Busy') { $color = '#007AFF'; $kind = 'Busy' }
        $row.Label.Text = $item.Label; $row.Value.Text = $item.Value
        $row.Value.ForeColor = ConvertTo-CampusColor $color
        $row.Glyph.Kind = $kind; $row.Glyph.AccentColor = $row.Value.ForeColor
        $Ui.ToolTips.SetToolTip($row.Value, $item.Value)
    }
    $Ui.DiagnosticTextBox.Text = $Text
}

function Show-CampusUiPage {
    param([hashtable]$Ui, [ValidateSet('Status', 'Account', 'Diagnostics', 'Logs')][string]$Page)
    foreach ($entry in $Ui.Pages.GetEnumerator()) { $entry.Value.Visible = $entry.Key -eq $Page }
    foreach ($entry in $Ui.Navigation.GetEnumerator()) {
        $selected = $entry.Key -eq $Page
        $entry.Value.BackColor = ConvertTo-CampusColor $(if ($selected) { '#EAF2FF' } else { '#F7F7FA' })
        $entry.Value.ForeColor = ConvertTo-CampusColor $(if ($selected) { '#007AFF' } else { '#636369' })
        $Ui.NavigationGlyphs[$entry.Key].AccentColor = $entry.Value.ForeColor
    }
    $Ui.Pages[$Page].BringToFront(); $Ui.ActivePage = $Page
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
    $Ui.StatusTextLabel.Text = [string]$Model.StatusText; $Ui.DetailLabel.Text = [string]$Model.DetailText
    $Ui.LastLoginLabel.Text = Format-CampusUiTime ([string]$Model.LastLoginAt)
    $Ui.LastErrorLabel.Text = [string]$Model.LastError
    if ([string]::IsNullOrWhiteSpace($Ui.LastErrorLabel.Text)) { $Ui.LastErrorLabel.Text = '暂无异常' }
    $Ui.UpdatedAtLabel.Text = Format-CampusUiTime ([string]$Model.UpdatedAt) '—'
    $Ui.SuggestionLabel.Text = [string]$Model.Suggestion
    if ([string]::IsNullOrWhiteSpace($Ui.SuggestionLabel.Text)) { $Ui.SuggestionLabel.Text = '首次确认未登录后立即尝试认证，失败时按间隔重试。' }
    $Ui.ToolTips.SetToolTip($Ui.DetailLabel, $Ui.DetailLabel.Text)
    $Ui.ToolTips.SetToolTip($Ui.LastErrorLabel, $Ui.LastErrorLabel.Text)
    $Ui.ToolTips.SetToolTip($Ui.SuggestionLabel, $Ui.SuggestionLabel.Text)
    $accent = '#D98600'; $tint = '#FFF5E6'; $glyph = 'Warning'; $badge = '待检查'; $monitorText = '运行中'
    switch ([string]$Model.MonitorState) {
        'Starting' { $monitorText = '正在启动'; $glyph = 'Busy'; $badge = '检查中'; $accent = '#007AFF'; $tint = '#EBF3FF' }
        'LoggingIn' { $monitorText = '正在自动登录'; $glyph = 'Busy'; $badge = '登录中'; $accent = '#007AFF'; $tint = '#EBF3FF' }
        'RetryWaiting' { $monitorText = '等待重试'; $badge = '等待重试' }
        'Error' { $monitorText = '需要检查' }
        'Stopped' { $monitorText = '已暂停' }
    }
    if ($Model.AuthState -eq 'Online' -and $Model.MonitorState -notin @('Error', 'LoggingIn', 'Starting', 'RetryWaiting')) {
        $accent = '#248A3D'; $tint = '#EAF8EE'; $glyph = 'Online'; $badge = '已连接'
    }
    if (-not $Model.MonitorRunning -and $Model.MonitorState -ne 'Error') {
        $monitorText = '已暂停'; $accent = '#8E8E93'; $tint = '#F0F0F4'; $glyph = 'Paused'; $badge = '已暂停'
    }
    $Ui.StatusTextLabel.ForeColor = ConvertTo-CampusColor '#1C1C1E'
    $Ui.MonitorStateLabel.Text = '自动监测：' + $monitorText
    $Ui.StatusGlyph.Kind = $glyph; $Ui.StatusGlyph.AccentColor = ConvertTo-CampusColor $accent
    $Ui.StatusIconWell.BackColor = ConvertTo-CampusColor $tint; $Ui.StatusIconWell.BorderColor = $Ui.StatusIconWell.BackColor
    $Ui.StatusBadge.BackColor = $Ui.StatusIconWell.BackColor; $Ui.StatusBadge.BorderColor = $Ui.StatusBadge.BackColor
    $Ui.BadgeLabel.Text = $badge; $Ui.BadgeLabel.ForeColor = ConvertTo-CampusColor $accent
    $Ui.ToggleMonitorButton.Text = if ($Model.MonitorRunning) { '暂停监测' } else { '开始监测' }
    $Ui.CheckNowButton.Enabled = [bool]$Model.MonitorRunning
    $Ui.VpnStateLabel.Text = if ($Model.VpnActive) { 'VPN 已启用  ·  校园网认证地址需直连' } else { '未检测到活动 VPN 隧道' }
    $Ui.ClearCredentialButton.Enabled = [bool]$Model.CredentialAvailable
    $Ui.CredentialStateLabel.Text = if ($Model.CredentialAvailable) { '密码已加密，只保存在这台电脑。' } else { '填写并保存账号后，即可开始自动监测。' }
}
