# Windows PowerShell 5.1. UI construction only, with no credential or network access.
. (Join-Path $PSScriptRoot 'CampusNetwork.UiControls.ps1')
. (Join-Path $PSScriptRoot 'CampusNetwork.Presentation.ps1')

function ConvertTo-CampusColor([string]$Hex) { return [Drawing.ColorTranslator]::FromHtml($Hex) }

function New-CampusUiLabel {
    param([string]$Text, [float]$Size = 10, [string]$Color = '#CBD5E1', [switch]$Bold, [switch]$Mono)
    $label = New-Object Windows.Forms.Label
    $label.Text = $Text; $label.AutoSize = $false; $label.Dock = 'Fill'
    $label.BackColor = [Drawing.Color]::Transparent
    $label.Margin = New-Object Windows.Forms.Padding(0)
    $style = if ($Bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }
    $family = if ($Mono) { 'Consolas' } else { 'Microsoft YaHei UI' }
    $label.Font = New-Object Drawing.Font($family, $Size, $style)
    $label.ForeColor = ConvertTo-CampusColor $Color; $label.TextAlign = 'MiddleLeft'
    return $label
}

function New-CampusUiButton {
    param([string]$Text, [string]$Name, [switch]$Primary, [int]$Width = 120, [switch]$Navigation, [switch]$Danger)
    $button = New-Object Windows.Forms.Button
    $button.FlatStyle = 'Flat'; $button.UseVisualStyleBackColor = $false
    $button.FlatAppearance.BorderSize = if ($Navigation) { 0 } else { 1 }
    $button.FlatAppearance.BorderColor = ConvertTo-CampusColor '#334155'
    $button.FlatAppearance.MouseOverBackColor = ConvertTo-CampusColor '#334155'
    $button.FlatAppearance.MouseDownBackColor = ConvertTo-CampusColor '#334155'
    $button.Name = $Name; $button.Text = $Text
    $button.Size = New-Object Drawing.Size($Width, 36)
    $button.Margin = New-Object Windows.Forms.Padding(0, 0, 8, 0)
    $button.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9.5)
    $button.Cursor = 'Hand'
    $button.BackColor = ConvertTo-CampusColor '#1E293B'; $button.ForeColor = ConvertTo-CampusColor '#38BDF8'
    if ($Primary) {
        # The spec's #F97316/white pair is only 2.80:1. Deeper orange keeps
        # the requested white type readable in every interaction state.
        $button.BackColor = ConvertTo-CampusColor '#C2410C'; $button.ForeColor = [Drawing.Color]::White
        $button.FlatAppearance.BorderSize = 0
        $button.FlatAppearance.BorderColor = $button.BackColor
        $button.FlatAppearance.MouseOverBackColor = ConvertTo-CampusColor '#9A3412'
        $button.FlatAppearance.MouseDownBackColor = ConvertTo-CampusColor '#7C2D12'
    }
    if ($Danger) {
        $button.ForeColor = ConvertTo-CampusColor '#F87171'
        $button.FlatAppearance.BorderColor = ConvertTo-CampusColor '#EF4444'
        $button.FlatAppearance.MouseOverBackColor = ConvertTo-CampusColor '#450A0A'
        $button.FlatAppearance.MouseDownBackColor = ConvertTo-CampusColor '#5F1414'
    }
    $normalBack = $button.BackColor; $normalText = $button.ForeColor
    $button.add_EnabledChanged({ param($sender, $eventArgs)
        $sender.Cursor = if ($sender.Enabled) { [Windows.Forms.Cursors]::Hand } else { [Windows.Forms.Cursors]::Default }
        $sender.BackColor = if ($sender.Enabled) { $normalBack } else { [Drawing.ColorTranslator]::FromHtml('#334155') }
        $sender.ForeColor = if ($sender.Enabled) { $normalText } else { [Drawing.ColorTranslator]::FromHtml('#94A3B8') }
    }.GetNewClosure())
    $button.add_Paint({ param($sender, $eventArgs)
        # Native FlatStyle paints disabled text using system colors, ignoring
        # ForeColor. Keep the native Button and repaint only its disabled face.
        if ($sender.Enabled) { return }
        $fill = New-Object Drawing.SolidBrush($sender.BackColor)
        try { $eventArgs.Graphics.FillRectangle($fill,$sender.ClientRectangle) } finally { $fill.Dispose() }
        if ($sender.FlatAppearance.BorderSize -gt 0) {
            $pen = New-Object Drawing.Pen($sender.FlatAppearance.BorderColor)
            try { $eventArgs.Graphics.DrawRectangle($pen,0,0,($sender.Width-1),($sender.Height-1)) } finally { $pen.Dispose() }
        }
        $flags = [Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [Windows.Forms.TextFormatFlags]::VerticalCenter -bor [Windows.Forms.TextFormatFlags]::SingleLine
        [Windows.Forms.TextRenderer]::DrawText($eventArgs.Graphics,$sender.Text,$sender.Font,$sender.ClientRectangle,$sender.ForeColor,$flags)
    })
    return $button
}

function New-CampusUiCard {
    param([int]$Padding = 20)
    $panel = New-Object CampusNetwork.UI.RoundedPanel
    $panel.Dock = 'Fill'; $panel.BackColor = ConvertTo-CampusColor '#1E293B'; $panel.Radius = 12
    $panel.BorderColor = ConvertTo-CampusColor '#334155'
    $panel.Padding = New-Object Windows.Forms.Padding($Padding)
    $panel.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 12)
    return $panel
}

function New-CampusNavButton([string]$Text, [string]$Name, [string]$Tag) {
    $button = New-CampusUiButton $Text $Name -Navigation
    $button.Tag = $Tag; $button.TextAlign = 'MiddleLeft'
    $button.Padding = New-Object Windows.Forms.Padding(44, 0, 0, 0)
    $button.BackColor = ConvertTo-CampusColor '#1E293B'; $button.ForeColor = ConvertTo-CampusColor '#CBD5E1'
    $button | Add-Member -NotePropertyName Hover -NotePropertyValue $false -Force
    $button.add_MouseEnter({ param($sender, $eventArgs) $sender.Hover = $true; $sender.Invalidate($true) })
    $button.add_MouseLeave({ param($sender, $eventArgs)
        $sender.Hover = $sender.ClientRectangle.Contains($sender.PointToClient([Windows.Forms.Control]::MousePosition))
        $sender.Invalidate($true)
    })
    $button.add_Paint({
        param($sender, $eventArgs)
        # Native flat buttons paint square corners and a system focus ring.
        # Draw the whole face here so the sidebar can use a pill highlight
        # with a left accent bar, matching the card language of the pages.
        $graphics = $eventArgs.Graphics
        # Clear every edge pixel before antialiasing the rounded surface. Otherwise
        # the native button's hover paint leaks through the half-covered perimeter.
        $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::None
        $scale = $graphics.DpiX / 96
        $parentColor = if ($null -ne $sender.Parent) { $sender.Parent.BackColor } else { $sender.BackColor }
        $fill = New-Object Drawing.SolidBrush($parentColor)
        try { $graphics.FillRectangle($fill, $sender.ClientRectangle) } finally { $fill.Dispose() }
        $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $selected = $sender.BackColor.ToArgb() -ne [Drawing.ColorTranslator]::FromHtml('#1E293B').ToArgb()
        $surface = $sender.BackColor
        if (-not $selected -and $sender.Hover) { $surface = [Drawing.ColorTranslator]::FromHtml('#26344A') }
        $radius = 8 * $scale
        $bounds = New-Object Drawing.RectangleF((1 * $scale), (2 * $scale), [Math]::Max(1, $sender.Width - 2 * $scale), [Math]::Max(1, $sender.Height - 4 * $scale))
        $path = New-Object Drawing.Drawing2D.GraphicsPath
        try {
            $diameter = [Math]::Min($radius * 2, [Math]::Min($bounds.Width, $bounds.Height))
            $path.AddArc($bounds.Left, $bounds.Top, $diameter, $diameter, 180, 90)
            $path.AddArc($bounds.Right - $diameter, $bounds.Top, $diameter, $diameter, 270, 90)
            $path.AddArc($bounds.Right - $diameter, $bounds.Bottom - $diameter, $diameter, $diameter, 0, 90)
            $path.AddArc($bounds.Left, $bounds.Bottom - $diameter, $diameter, $diameter, 90, 90)
            $path.CloseFigure()
            $brush = New-Object Drawing.SolidBrush($surface)
            try { $graphics.FillPath($brush, $path) } finally { $brush.Dispose() }
        } finally { $path.Dispose() }
        if ($selected) {
            $bar = New-Object Drawing.Drawing2D.GraphicsPath
            try {
                $barWidth = 3 * $scale; $barHeight = [Math]::Max(6, $bounds.Height - 20 * $scale)
                $barTop = $bounds.Top + ($bounds.Height - $barHeight) / 2
                $barDiameter = $barWidth
                $bar.AddArc($bounds.Left + 1 * $scale, $barTop, $barDiameter, $barDiameter, 180, 180)
                $bar.AddArc($bounds.Left + 1 * $scale, $barTop + $barHeight - $barDiameter, $barDiameter, $barDiameter, 0, 180)
                $bar.CloseFigure()
                $accent = New-Object Drawing.SolidBrush($sender.ForeColor)
                try { $graphics.FillPath($accent, $bar) } finally { $accent.Dispose() }
            } finally { $bar.Dispose() }
        }
        # WinForms has already scaled Padding with the control.
        $textBounds = New-Object Drawing.Rectangle($sender.Padding.Left, 0,
            [Math]::Max(1, $sender.Width - $sender.Padding.Left - [int](10 * $scale)), $sender.Height)
        [Windows.Forms.TextRenderer]::DrawText($graphics, $sender.Text, $sender.Font, $textBounds, $sender.ForeColor,
            ([Windows.Forms.TextFormatFlags]::Left -bor [Windows.Forms.TextFormatFlags]::VerticalCenter -bor
             [Windows.Forms.TextFormatFlags]::SingleLine -bor [Windows.Forms.TextFormatFlags]::EndEllipsis -bor
             [Windows.Forms.TextFormatFlags]::NoPrefix))
        if ($sender.Focused -and [CampusNetwork.UI.FlatControlDrawing]::KeyboardFocusVisible) {
            $focusPath = New-Object Drawing.Drawing2D.GraphicsPath
            try {
                $focusBounds = $bounds; $focusBounds.Inflate(-1.5 * $scale, -1.5 * $scale)
                $focusDiameter = [Math]::Min(($radius + 1) * 2, [Math]::Min($focusBounds.Width, $focusBounds.Height))
                $focusPath.AddArc($focusBounds.Left, $focusBounds.Top, $focusDiameter, $focusDiameter, 180, 90)
                $focusPath.AddArc($focusBounds.Right - $focusDiameter, $focusBounds.Top, $focusDiameter, $focusDiameter, 270, 90)
                $focusPath.AddArc($focusBounds.Right - $focusDiameter, $focusBounds.Bottom - $focusDiameter, $focusDiameter, $focusDiameter, 0, 90)
                $focusPath.AddArc($focusBounds.Left, $focusBounds.Bottom - $focusDiameter, $focusDiameter, $focusDiameter, 90, 90)
                $focusPath.CloseFigure()
                $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(140, $sender.ForeColor), 1.2 * $scale)
                try { $graphics.DrawPath($pen, $focusPath) } finally { $pen.Dispose() }
            } finally { $focusPath.Dispose() }
        }
    })
    $button.add_GotFocus({ param($sender, $eventArgs) $sender.Invalidate() })
    $button.add_LostFocus({ param($sender, $eventArgs) $sender.Invalidate() })
    return $button
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

function New-CampusGlyph([string]$Kind, [string]$Color = '#38BDF8', [int]$Size = 24) {
    $glyph = New-Object CampusNetwork.UI.StatusGlyph
    $glyph.Kind = $Kind; $glyph.AccentColor = ConvertTo-CampusColor $Color
    $glyph.Size = New-Object Drawing.Size($Size, $Size); $glyph.Margin = New-Object Windows.Forms.Padding(0)
    return $glyph
}

function New-CampusPageHeading([string]$Title, [string]$Subtitle) {
    $heading = New-CampusUiTable -Rows 3
    Add-CampusUiRow $heading 36; Add-CampusUiRow $heading 22; Add-CampusUiRow $heading 12
    [void]$heading.Controls.Add((New-CampusUiLabel $Title 19 '#F8FAFC' -Bold), 0, 0)
    [void]$heading.Controls.Add((New-CampusUiLabel $Subtitle 9.5 '#94A3B8'), 0, 1)
    $rule = New-Object Windows.Forms.Panel
    $rule.Dock = 'Fill'; $rule.Height = 1; $rule.Width = 36
    $rule.BackColor = ConvertTo-CampusColor '#38BDF8'; $rule.Margin = New-Object Windows.Forms.Padding(0, 10, 0, 0)
    $rule.Anchor = 'Left'
    $ruleHost = New-CampusUiTable -Rows 1 -Columns 2
    [void]$ruleHost.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 36)))
    [void]$ruleHost.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
    [void]$ruleHost.Controls.Add($rule, 0, 0)
    [void]$heading.Controls.Add($ruleHost, 0, 2)
    $heading.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 14)
    return $heading
}

function New-CampusFieldWell($Control) {
    $well = New-Object CampusNetwork.UI.RoundedPanel
    $well.Dock = 'Fill'; $well.Radius = 9
    $well.HighlightFocusWithin = $true
    $well.BackColor = ConvertTo-CampusColor '#0F172A'; $well.BorderColor = ConvertTo-CampusColor '#3B4A61'
    $well.FocusBorderColor = ConvertTo-CampusColor '#38BDF8'
    $well.Padding = New-Object Windows.Forms.Padding(12, 8, 12, 8)
    $well.Margin = New-Object Windows.Forms.Padding(0, 2, 0, 2)
    $Control.Dock = 'Fill'; $Control.Margin = New-Object Windows.Forms.Padding(0)
    $Control.BackColor = $well.BackColor; $Control.ForeColor = ConvertTo-CampusColor '#F8FAFC'
    $Control.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10)
    if ($Control -is [CampusNetwork.UI.RoundedComboBox]) { $Control.AccentColor = ConvertTo-CampusColor '#38BDF8' }
    [void]$well.Controls.Add($Control)
    return $well
}

function New-CampusPreferenceRow([string]$Title, [string]$Note, $Toggle) {
    $row = New-CampusUiTable -Rows 2 -Columns 2
    [void]$row.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 30)))
    [void]$row.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
    Add-CampusUiRow $row 24; Add-CampusUiRow $row 20
    $Toggle.Dock = 'Fill'; $Toggle.Margin = New-Object Windows.Forms.Padding(0, 1, 6, 0)
    $Toggle.AutoSize = $false; $Toggle.FlatStyle = 'Flat'
    # Normal-appearance native CheckBox ignores CheckedBackColor. Paint the
    # glyph explicitly while retaining native keyboard and CheckedChanged behavior.
    $Toggle.ForeColor = ConvertTo-CampusColor '#F8FAFC'
    $Toggle.BackColor = ConvertTo-CampusColor '#1E293B'
    $Toggle.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10)
    $Toggle.FlatAppearance.BorderColor = ConvertTo-CampusColor '#64748B'
    $Toggle.FlatAppearance.CheckedBackColor = ConvertTo-CampusColor '#0EA5E9'
    $Toggle.FlatAppearance.MouseOverBackColor = ConvertTo-CampusColor '#334155'
    $Toggle.FlatAppearance.MouseDownBackColor = ConvertTo-CampusColor '#334155'
    $Toggle.AccessibleName = $Title; $Toggle.Text = ''
    $Toggle | Add-Member -NotePropertyName Hover -NotePropertyValue $false -Force
    $Toggle | Add-Member -NotePropertyName Pressed -NotePropertyValue $false -Force
    $Toggle.add_Paint({ param($sender,$eventArgs)
        [CampusNetwork.UI.FlatControlDrawing]::PaintCheckBox($sender,$eventArgs.Graphics,[bool]$sender.Hover,[bool]$sender.Pressed)
    })
    $Toggle.add_MouseEnter({ param($sender,$eventArgs) $sender.Hover=$true; $sender.Invalidate() })
    $Toggle.add_MouseLeave({ param($sender,$eventArgs) $sender.Hover=$false; $sender.Pressed=$false; $sender.Invalidate() })
    $Toggle.add_MouseDown({ param($sender,$eventArgs) if ($eventArgs.Button -eq [Windows.Forms.MouseButtons]::Left) { $sender.Pressed=$true; $sender.Invalidate() } })
    $Toggle.add_MouseUp({ param($sender,$eventArgs) $sender.Pressed=$false; $sender.Invalidate() })
    $Toggle.add_KeyDown({ param($sender,$eventArgs) if ($eventArgs.KeyCode -eq [Windows.Forms.Keys]::Space) { $sender.Pressed=$true; $sender.Invalidate() } })
    $Toggle.add_KeyUp({ param($sender,$eventArgs) $sender.Pressed=$false; $sender.Invalidate() })
    $Toggle.add_GotFocus({ param($sender,$eventArgs) $sender.Invalidate() })
    $Toggle.add_LostFocus({ param($sender,$eventArgs) $sender.Pressed=$false; $sender.Invalidate() })
    $Toggle.add_EnabledChanged({ param($sender,$eventArgs) $sender.Pressed=$false; $sender.Hover=$false; $sender.Invalidate() })
    $titleLabel = New-CampusUiLabel $Title 10.5 '#F8FAFC'; $titleLabel.Cursor = 'Hand'
    $titleLabel.add_Click({ if ($Toggle.Enabled) { [void]$Toggle.Focus(); $Toggle.Checked = -not $Toggle.Checked } }.GetNewClosure())
    $description = New-CampusUiLabel $Note 9 '#94A3B8'
    [void]$row.Controls.Add($Toggle, 0, 0); [void]$row.Controls.Add($titleLabel, 1, 0)
    [void]$row.Controls.Add($description, 1, 1)
    return $row
}

function New-CampusUiSeparator {
    $line = New-Object Windows.Forms.Panel
    $line.Dock = 'Top'; $line.Height = 1; $line.BackColor = ConvertTo-CampusColor '#334155'
    $line.Margin = New-Object Windows.Forms.Padding(0)
    return $line
}

function New-CampusTrayView {
    $ui = @{}
    $form = New-Object Windows.Forms.Form
    $form.Name = 'campusNetworkForm'; $form.Text = '校园网助手'
    $form.ClientSize = New-Object Drawing.Size(1080, 780); $form.MinimumSize = New-Object Drawing.Size(980, 720)
    $form.StartPosition = 'CenterScreen'; $form.AutoScaleMode = 'Dpi'
    $form.AutoScaleDimensions = New-Object Drawing.SizeF(96, 96)
    $form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9.5)
    $form.BackColor = ConvertTo-CampusColor '#0F172A'; $ui.Form = $form
    # Keep the stock white caption from cutting the dark window in half.
    $form.add_HandleCreated({
        [void][CampusNetwork.UI.DarkTitleBar]::Apply($this.Handle,
            [Drawing.ColorTranslator]::FromHtml('#0F172A'),
            [Drawing.ColorTranslator]::FromHtml('#E2E8F0'),
            [Drawing.ColorTranslator]::FromHtml('#1E293B'))
        # Switch the process to dark theming before native child controls
        # (scroll bars, drop-down list) create their own windows.
        [void][CampusNetwork.UI.DarkScrollbars]::Apply($this.Handle)
    })
    $ui.ToolTips = New-Object Windows.Forms.ToolTip
    $ui.ToolTips.AutoPopDelay = 15000
    $hintProvider = $ui.ToolTips
    $form.add_Disposed({ $hintProvider.Dispose() }.GetNewClosure())
    $root = New-CampusUiTable -Rows 2
    Add-CampusUiRow $root 100 -Percent; Add-CampusUiRow $root 30
    [void]$form.Controls.Add($root)
    $body = New-CampusUiTable -Rows 1 -Columns 2
    [void]$body.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 208)))
    [void]$body.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
    [void]$root.Controls.Add($body, 0, 0)

    $nav = New-CampusUiTable -Rows 8
    $nav.BackColor = ConvertTo-CampusColor '#1E293B'; $nav.Padding = New-Object Windows.Forms.Padding(16, 26, 16, 20)
    @(84, 30, 44, 44, 44, 44) | ForEach-Object { Add-CampusUiRow $nav $_ }
    Add-CampusUiRow $nav 100 -Percent; Add-CampusUiRow $nav 96
    $brand = New-CampusUiTable -Rows 1 -Columns 2
    [void]$brand.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 48)))
    [void]$brand.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
    $brandIcon = New-Object CampusNetwork.UI.RoundedPanel
    $brandIcon.Size = New-Object Drawing.Size(38, 38); $brandIcon.Radius = 11
    $brandIcon.BackColor = ConvertTo-CampusColor '#0EA5E9'; $brandIcon.BorderColor = ConvertTo-CampusColor '#7DD3FC'
    $brandIcon.Padding = New-Object Windows.Forms.Padding(8); $brandIcon.Margin = New-Object Windows.Forms.Padding(0, 9, 0, 0)
    $wifi = New-CampusGlyph 'Wifi' '#F8FAFC'; $wifi.Dock = 'Fill'; $wifi.LineWidth = 1.9
    [void]$brandIcon.Controls.Add($wifi)
    $brandCopy = New-CampusUiTable -Rows 2
    $brandCopy.Dock = 'Top'; $brandCopy.Height = 62
    Add-CampusUiRow $brandCopy 32; Add-CampusUiRow $brandCopy 24
    [void]$brandCopy.Controls.Add((New-CampusUiLabel '校园网助手' 12.5 '#F8FAFC' -Bold), 0, 0)
    [void]$brandCopy.Controls.Add((New-CampusUiLabel '自动认证与重连' 9 '#94A3B8'), 0, 1)
    [void]$brand.Controls.Add($brandIcon, 0, 0); [void]$brand.Controls.Add($brandCopy, 1, 0)
    [void]$nav.Controls.Add($brand, 0, 0)
    $navTitle = New-CampusUiLabel '校园网络' 8.5 '#94A3B8'; $navTitle.Padding = New-Object Windows.Forms.Padding(12, 0, 0, 0)
    [void]$nav.Controls.Add($navTitle, 0, 1)
    $ui.Navigation = @{}; $ui.NavigationGlyphs = @{}
    $navItems = @(@('Status', '连接概览', 'Wifi'), @('Account', '账号与设置', 'Settings'), @('Diagnostics', '网络诊断', 'Diagnostics'), @('Logs', '运行日志', 'Logs'))
    $index = 2
    foreach ($item in $navItems) {
        $button = New-CampusNavButton $item[1] ('nav' + $item[0]) $item[0]; $button.Dock = 'Fill'
        $button.Margin = New-Object Windows.Forms.Padding(0, 1, 0, 1)
        $glyph = New-CampusGlyph $item[2] '#CBD5E1' 18; $glyph.Location = New-Object Drawing.Point(15, 12)
        $glyph.add_Click({ param($sender, $eventArgs) $sender.Parent.PerformClick() })
        $glyph.add_MouseEnter({ param($sender, $eventArgs) $sender.Parent.Hover=$true; $sender.Parent.Invalidate($true) })
        $glyph.add_MouseLeave({ param($sender, $eventArgs)
            $button=$sender.Parent
            $button.Hover=$button.ClientRectangle.Contains($button.PointToClient([Windows.Forms.Control]::MousePosition))
            $button.Invalidate($true)
        })
        [void]$button.Controls.Add($glyph); [void]$nav.Controls.Add($button, 0, $index)
        $ui.Navigation[$item[0]] = $button; $ui.NavigationGlyphs[$item[0]] = $glyph; $index++
    }
    $navFoot = New-CampusUiTable -Rows 4
    Add-CampusUiRow $navFoot 26; Add-CampusUiRow $navFoot 20; Add-CampusUiRow $navFoot 38; Add-CampusUiRow $navFoot 12
    [void]$navFoot.Controls.Add((New-CampusGlyph 'Shield' '#64748B' 18), 0, 0)
    [void]$navFoot.Controls.Add((New-CampusUiLabel '凭据只保存在本机' 9.5 '#94A3B8'), 0, 1)
    [void]$navFoot.Controls.Add((New-CampusUiLabel "关闭窗口后继续运行。`r`n双击托盘图标返回。" 9 '#94A3B8'), 0, 2)
    [void]$nav.Controls.Add($navFoot, 0, 7); [void]$body.Controls.Add($nav, 0, 0)
    $content = New-Object CampusNetwork.UI.SurfacePanel
    $content.Dock = 'Fill'; $content.Margin = New-Object Windows.Forms.Padding(0)
    $content.BackColor = ConvertTo-CampusColor '#0F172A'
    $content.MotifColor = [Drawing.Color]::FromArgb(30, 56, 189, 248)
    $content.Padding = New-Object Windows.Forms.Padding(30, 26, 30, 12)
    [void]$body.Controls.Add($content, 1, 0); $ui.Pages = @{}

    $statusPage = New-CampusUiTable -Rows 5
    Add-CampusUiRow $statusPage 84; Add-CampusUiRow $statusPage 254
    Add-CampusUiRow $statusPage 156; Add-CampusUiRow $statusPage 84; Add-CampusUiRow $statusPage 100 -Percent
    [void]$statusPage.Controls.Add((New-CampusPageHeading '连接概览' '查看认证状态与自动监测情况。'), 0, 0)
    $connectionCard = New-CampusUiCard -Padding 22
    $connection = New-CampusUiTable -Rows 4
    Add-CampusUiRow $connection 60; Add-CampusUiRow $connection 48; Add-CampusUiRow $connection 32; Add-CampusUiRow $connection 44
    $headline = New-CampusUiTable -Rows 1 -Columns 3
    [void]$headline.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 72)))
    [void]$headline.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
    [void]$headline.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 102)))
    $ui.StatusIconWell = New-Object CampusNetwork.UI.RoundedPanel
    $ui.StatusIconWell.Size = New-Object Drawing.Size(54, 54); $ui.StatusIconWell.Radius = 15
    $ui.StatusIconWell.BackColor = ConvertTo-CampusColor '#064E3B'; $ui.StatusIconWell.BorderColor = ConvertTo-CampusColor '#0F766E'
    $ui.StatusIconWell.Padding = New-Object Windows.Forms.Padding(13); $ui.StatusIconWell.Margin = New-Object Windows.Forms.Padding(0, 3, 0, 0)
    $ui.StatusGlyph = New-CampusGlyph 'Online' '#10B981' 28; $ui.StatusGlyph.Dock = 'Fill'
    [void]$ui.StatusIconWell.Controls.Add($ui.StatusGlyph)
    $statusCopy = New-CampusUiTable -Rows 2
    Add-CampusUiRow $statusCopy 34; Add-CampusUiRow $statusCopy 24
    $ui.StatusTextLabel = New-CampusUiLabel '正在读取连接状态' 19 '#F8FAFC' -Bold; $ui.StatusTextLabel.Name = 'statusTextLabel'
    $ui.MonitorStateLabel = New-CampusUiLabel '自动监测：正在初始化' 9.5 '#94A3B8'; $ui.MonitorStateLabel.Name = 'monitorStateLabel'
    [void]$statusCopy.Controls.Add($ui.StatusTextLabel, 0, 0); [void]$statusCopy.Controls.Add($ui.MonitorStateLabel, 0, 1)
    $ui.StatusBadge = New-Object CampusNetwork.UI.RoundedPanel
    $ui.StatusBadge.Size = New-Object Drawing.Size(94, 26); $ui.StatusBadge.Radius = 13; $ui.StatusBadge.Anchor = 'Top,Right'
    $ui.StatusBadge.Padding = New-Object Windows.Forms.Padding(6, 2, 6, 2); $ui.StatusBadge.Margin = New-Object Windows.Forms.Padding(0, 6, 0, 0)
    $ui.BadgeLabel = New-CampusUiLabel '检查中' 8.5 '#94A3B8'; $ui.BadgeLabel.TextAlign = 'MiddleCenter'
    [void]$ui.StatusBadge.Controls.Add($ui.BadgeLabel)
    [void]$headline.Controls.Add($ui.StatusBadge, 2, 0)
    [void]$headline.Controls.Add($ui.StatusIconWell, 0, 0); [void]$headline.Controls.Add($statusCopy, 1, 0)
    $ui.DetailLabel = New-CampusUiLabel '启动后会自动读取校园网认证状态。' 10 '#CBD5E1'; $ui.DetailLabel.Name = 'detailLabel'
    $ui.DetailLabel.AutoEllipsis = $true
    $ui.DetailLabel.TextAlign = 'TopLeft'; $ui.DetailLabel.Padding = New-Object Windows.Forms.Padding(0, 6, 0, 0)
    $vpnWell = New-Object CampusNetwork.UI.RoundedPanel
    $vpnWell.Dock = 'Fill'; $vpnWell.Radius = 8; $vpnWell.Margin = New-Object Windows.Forms.Padding(0, 1, 0, 1)
    $vpnWell.BackColor = ConvertTo-CampusColor '#0F172A'; $vpnWell.BorderColor = ConvertTo-CampusColor '#293548'
    $vpnWell.Padding = New-Object Windows.Forms.Padding(12, 0, 12, 0)
    $ui.VpnGlyph = New-CampusGlyph 'Shield' '#64748B' 14; $ui.VpnGlyph.Location = New-Object Drawing.Point(12, 9)
    $ui.VpnStateLabel = New-CampusUiLabel 'VPN 状态：正在读取' 9 '#94A3B8'; $ui.VpnStateLabel.Name = 'vpnStateLabel'
    $ui.VpnStateLabel.Padding = New-Object Windows.Forms.Padding(20, 0, 0, 0)
    [void]$vpnWell.Controls.Add($ui.VpnGlyph); [void]$vpnWell.Controls.Add($ui.VpnStateLabel)
    [void]$connection.Controls.Add($headline, 0, 0); [void]$connection.Controls.Add($ui.DetailLabel, 0, 1); [void]$connection.Controls.Add($vpnWell, 0, 2)
    [void]$connectionCard.Controls.Add($connection); [void]$statusPage.Controls.Add($connectionCard, 0, 1)
    $historyCard = New-CampusUiCard -Padding 20
    $history = New-CampusUiTable -Rows 3 -Columns 2
    [void]$history.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 130)))
    [void]$history.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
    Add-CampusUiRow $history 28; Add-CampusUiRow $history 46; Add-CampusUiRow $history 28
    [void]$history.Controls.Add((New-CampusUiLabel '最近自动登录' 9 '#94A3B8'), 0, 0)
    [void]$history.Controls.Add((New-CampusUiLabel '最近异常' 9 '#94A3B8'), 0, 1)
    [void]$history.Controls.Add((New-CampusUiLabel '状态更新' 9 '#94A3B8'), 0, 2)
    $ui.LastLoginLabel = New-CampusUiLabel '暂无记录' 9.5 '#CBD5E1' -Mono; $ui.LastLoginLabel.Name = 'lastLoginLabel'
    $ui.LastErrorLabel = New-CampusUiLabel '暂无异常' 9.5 '#CBD5E1'; $ui.LastErrorLabel.Name = 'lastErrorLabel'
    $ui.LastErrorLabel.AutoEllipsis = $true
    $ui.UpdatedAtLabel = New-CampusUiLabel '—' 9.5 '#CBD5E1' -Mono
    [void]$history.Controls.Add($ui.LastLoginLabel, 1, 0); [void]$history.Controls.Add($ui.LastErrorLabel, 1, 1); [void]$history.Controls.Add($ui.UpdatedAtLabel, 1, 2)
    [void]$historyCard.Controls.Add($history); [void]$statusPage.Controls.Add($historyCard, 0, 2)
    $actions = New-Object Windows.Forms.FlowLayoutPanel
    $actions.Dock = 'Fill'; $actions.Margin = New-Object Windows.Forms.Padding(0, 12, 0, 0)
    $ui.ToggleMonitorButton = New-CampusUiButton '暂停监测' 'toggleMonitorButton' -Primary -Width 112
    $ui.CheckNowButton = New-CampusUiButton '立即检查' 'checkNowButton' -Width 112
    [void]$actions.Controls.Add($ui.ToggleMonitorButton); [void]$actions.Controls.Add($ui.CheckNowButton)
    [void]$connection.Controls.Add($actions, 0, 3)
    $ui.SuggestionLabel = New-CampusUiLabel '首次确认未登录后立即尝试认证，失败时按间隔重试。' 9.5 '#94A3B8'
    $ui.SuggestionLabel.Name = 'suggestionLabel'; $ui.SuggestionLabel.TextAlign = 'TopLeft'
    $ui.SuggestionLabel.AutoEllipsis = $true
    $ui.SuggestionLabel.Padding = New-Object Windows.Forms.Padding(2, 4, 2, 0)
    [void]$statusPage.Controls.Add($ui.SuggestionLabel, 0, 3); $ui.Pages.Status = $statusPage

    $accountPage = New-CampusUiTable -Rows 5
    Add-CampusUiRow $accountPage 84; Add-CampusUiRow $accountPage 330; Add-CampusUiRow $accountPage 26
    Add-CampusUiRow $accountPage 152; Add-CampusUiRow $accountPage 100 -Percent
    [void]$accountPage.Controls.Add((New-CampusPageHeading '账号与设置' '管理本机账号与自动监测偏好。'), 0, 0)
    $accountCard = New-CampusUiCard
    $accountTable = New-CampusUiTable -Rows 6 -Columns 2
    [void]$accountTable.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 104)))
    [void]$accountTable.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
    @(50, 50, 50, 40, 46, 24) | ForEach-Object { Add-CampusUiRow $accountTable $_ }
    $ui.AccountTextBox = New-Object Windows.Forms.TextBox
    $ui.AccountTextBox.Name = 'accountTextBox'; $ui.AccountTextBox.MaxLength = 128; $ui.AccountTextBox.BorderStyle = 'None'; $ui.AccountTextBox.AccessibleName = '校园网账号'
    $ui.CarrierComboBox = New-Object CampusNetwork.UI.RoundedComboBox
    $ui.CarrierComboBox.Name = 'carrierComboBox'; $ui.CarrierComboBox.DropDownStyle = 'DropDownList'; $ui.CarrierComboBox.FlatStyle = 'Flat'; $ui.CarrierComboBox.AccessibleName = '运营商'
    [void]$ui.CarrierComboBox.Items.AddRange(@('校园网', '中国联通', '中国移动', '中国电信')); $ui.CarrierComboBox.SelectedIndex = 1
    $ui.CarrierComboBox.add_HandleCreated({ param($sender, $eventArgs) [void][CampusNetwork.UI.DarkScrollbars]::Apply($sender.Handle) })
    $ui.PasswordTextBox = New-Object Windows.Forms.TextBox
    $ui.PasswordTextBox.Name = 'passwordTextBox'; $ui.PasswordTextBox.UseSystemPasswordChar = $true
    $ui.PasswordTextBox.MaxLength = 256; $ui.PasswordTextBox.BorderStyle = 'None'; $ui.PasswordTextBox.AccessibleName = '校园网密码'
    [void]$accountTable.Controls.Add((New-CampusUiLabel '校园网账号' 9.5 '#CBD5E1'), 0, 0)
    [void]$accountTable.Controls.Add((New-CampusUiLabel '运营商' 9.5 '#CBD5E1'), 0, 1)
    [void]$accountTable.Controls.Add((New-CampusUiLabel '密码' 9.5 '#CBD5E1'), 0, 2)
    [void]$accountTable.Controls.Add((New-CampusFieldWell $ui.AccountTextBox), 1, 0)
    [void]$accountTable.Controls.Add((New-CampusFieldWell $ui.CarrierComboBox), 1, 1)
    [void]$accountTable.Controls.Add((New-CampusFieldWell $ui.PasswordTextBox), 1, 2)
    $passwordHint = New-CampusUiLabel "账号与运营商不变时，留空保留原密码。`r`n更换账号或运营商时，请输入新密码。" 8.5 '#94A3B8'
    $passwordHint.Name = 'passwordHintLabel'; $passwordHint.TextAlign = 'TopLeft'
    $passwordHint.Padding = New-Object Windows.Forms.Padding(2, 4, 0, 0)
    [void]$accountTable.Controls.Add($passwordHint, 1, 3)
    $saveActions = New-Object Windows.Forms.FlowLayoutPanel
    $saveActions.Dock = 'Fill'; $saveActions.Margin = New-Object Windows.Forms.Padding(0, 4, 0, 0)
    $ui.SaveButton = New-CampusUiButton '保存账号' 'saveButton' -Primary -Width 120
    $ui.ClearCredentialButton = New-CampusUiButton '清除账号' 'clearCredentialButton' -Width 120 -Danger
    [void]$saveActions.Controls.Add($ui.SaveButton); [void]$saveActions.Controls.Add($ui.ClearCredentialButton)
    [void]$accountTable.Controls.Add($saveActions, 1, 4)
    $ui.CredentialStateLabel = New-CampusUiLabel '密码已加密，只保存在这台电脑。' 8.5 '#94A3B8'
    [void]$accountTable.Controls.Add($ui.CredentialStateLabel, 1, 5)
    [void]$accountCard.Controls.Add($accountTable)
    [void]$accountPage.Controls.Add($accountCard, 0, 1)
    $automationTitle = New-CampusUiTable -Rows 1 -Columns 2
    [void]$automationTitle.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 22)))
    [void]$automationTitle.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
    [void]$automationTitle.Controls.Add((New-CampusGlyph 'Pulse' '#64748B' 14), 0, 0)
    $automationLabel = New-CampusUiLabel '自动化' 9.5 '#94A3B8'; $automationLabel.Padding = New-Object Windows.Forms.Padding(0, 0, 0, 0)
    [void]$automationTitle.Controls.Add($automationLabel, 1, 0)
    [void]$accountPage.Controls.Add($automationTitle, 0, 2)
    $preferenceCard = New-CampusUiCard -Padding 20
    $preferences = New-CampusUiTable -Rows 3
    Add-CampusUiRow $preferences 46; Add-CampusUiRow $preferences 4; Add-CampusUiRow $preferences 46
    $ui.StartupCheckBox = New-Object Windows.Forms.CheckBox; $ui.StartupCheckBox.Name = 'startupCheckBox'
    $ui.MonitorOnLaunchCheckBox = New-Object Windows.Forms.CheckBox; $ui.MonitorOnLaunchCheckBox.Name = 'monitorOnLaunchCheckBox'
    [void]$preferences.Controls.Add((New-CampusPreferenceRow '登录 Windows 后启动' '在托盘中安静运行，随时查看连接状态。' $ui.StartupCheckBox), 0, 0)
    [void]$preferences.Controls.Add((New-CampusUiSeparator), 0, 1)
    [void]$preferences.Controls.Add((New-CampusPreferenceRow '打开助手时自动监测' '暂停后会记住你的选择，可随时手动开启。' $ui.MonitorOnLaunchCheckBox), 0, 2)
    [void]$preferenceCard.Controls.Add($preferences); [void]$accountPage.Controls.Add($preferenceCard, 0, 3)
    $ui.Pages.Account = $accountPage

    foreach ($definition in @(@('Diagnostics', '网络诊断', '查看检查结论与处理建议。'), @('Logs', '运行日志', '查看最近的认证与监测记录。'))) {
        $page = New-CampusUiTable -Rows 3
        Add-CampusUiRow $page 84; Add-CampusUiRow $page 62; Add-CampusUiRow $page 100 -Percent
        [void]$page.Controls.Add((New-CampusPageHeading $definition[1] $definition[2]), 0, 0)
        $toolbar = New-CampusUiTable -Rows 1 -Columns 2
        [void]$toolbar.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
        [void]$toolbar.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 148)))
        if ($definition[0] -eq 'Diagnostics') {
            $copy = "检查校园网认证、VPN 与服务端口。`r`n诊断在后台执行，你可以继续操作。"
            $ui.DiagnosisButton = New-CampusUiButton '开始诊断' 'diagnosisButton' -Primary -Width 120; $button = $ui.DiagnosisButton
        } else {
            $copy = "最近 100 条运行记录。`r`n选中相关文字即可复制。"
            $ui.RefreshLogsButton = New-CampusUiButton '刷新日志' 'refreshLogsButton' -Width 120; $button = $ui.RefreshLogsButton
        }
        $description = New-CampusUiLabel $copy 9.5 '#94A3B8'; $description.TextAlign = 'TopLeft'
        $description.Padding = New-Object Windows.Forms.Padding(0, 6, 0, 0)
        $button.Anchor = 'Top,Right'; $button.Margin = New-Object Windows.Forms.Padding(0, 5, 0, 0)
        [void]$toolbar.Controls.Add($description, 0, 0); [void]$toolbar.Controls.Add($button, 1, 0)
        [void]$page.Controls.Add($toolbar, 0, 1)
        $resultCard = New-CampusUiCard -Padding 22
        $textBox = New-Object Windows.Forms.RichTextBox
        $textBox.ReadOnly = $true; $textBox.Dock = 'Fill'; $textBox.BorderStyle = 'None'
        $textBox.BackColor = ConvertTo-CampusColor '#1E293B'; $textBox.ForeColor = ConvertTo-CampusColor '#CBD5E1'
        $textBox.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9.5); $textBox.DetectUrls = $false
        $textBox.Margin = New-Object Windows.Forms.Padding(0, 6, 0, 0)
        # Keep the result text inside a recessed well so the card reads as a
        # page with a panel, not a single flat block of text.
        $textWell = New-Object CampusNetwork.UI.RoundedPanel
        $textWell.Dock = 'Fill'; $textWell.Radius = 8
        $textWell.BackColor = ConvertTo-CampusColor '#16202F'; $textWell.BorderColor = ConvertTo-CampusColor '#293548'
        $textWell.Padding = New-Object Windows.Forms.Padding(14, 10, 6, 8)
        $textWell.Margin = New-Object Windows.Forms.Padding(0)
        $textBox.BackColor = $textWell.BackColor
        $textBox.add_HandleCreated({ param($sender, $eventArgs) [void][CampusNetwork.UI.DarkScrollbars]::Apply($sender.Handle) })
        $textBox.add_VisibleChanged({ param($sender, $eventArgs) if ($sender.Visible -and $sender.IsHandleCreated) { [void][CampusNetwork.UI.DarkScrollbars]::Apply($sender.Handle) } })
        [void]$textWell.Controls.Add($textBox)
        if ($definition[0] -eq 'Diagnostics') {
            $textBox.Name = 'diagnosticTextBox'; $ui.DiagnosticTextBox = $textBox
            $resultLayout = New-CampusUiTable -Rows 7
            Add-CampusUiRow $resultLayout 34; Add-CampusUiRow $resultLayout 32
            Add-CampusUiRow $resultLayout 120; Add-CampusUiRow $resultLayout 8
            Add-CampusUiRow $resultLayout 58; Add-CampusUiRow $resultLayout 30; Add-CampusUiRow $resultLayout 100 -Percent
            $ui.DiagnosticTitleLabel = New-CampusUiLabel '' 15 '#F8FAFC' -Bold
            $ui.DiagnosticSummaryLabel = New-CampusUiLabel '' 9.5 '#CBD5E1'; $ui.DiagnosticSummaryLabel.AutoEllipsis = $true
            [void]$resultLayout.Controls.Add($ui.DiagnosticTitleLabel, 0, 0)
            [void]$resultLayout.Controls.Add($ui.DiagnosticSummaryLabel, 0, 1)
            $checks = New-CampusUiTable -Rows 4 -Columns 3
            [void]$checks.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 58)))
            [void]$checks.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 30)))
            [void]$checks.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 42)))
            $ui.DiagnosticRows = @()
            for ($index = 0; $index -lt 4; $index++) {
                # Share the available height so fractional DPI scaling cannot
                # round each 29px row up independently and overflow the table.
                Add-CampusUiRow $checks 25 -Percent
                $label = New-CampusUiLabel '' 9.5 '#CBD5E1'
                $glyph = New-CampusGlyph 'Info' '#94A3B8' 16; $glyph.Anchor = 'Left'
                $value = New-CampusUiLabel '' 9.5 '#94A3B8'; $value.AutoEllipsis = $true
                [void]$checks.Controls.Add($label, 0, $index); [void]$checks.Controls.Add($glyph, 1, $index); [void]$checks.Controls.Add($value, 2, $index)
                $ui.DiagnosticRows += @{ Label = $label; Glyph = $glyph; Value = $value }
            }
            [void]$resultLayout.Controls.Add($checks, 0, 2)
            [void]$resultLayout.Controls.Add((New-CampusUiSeparator), 0, 3)
            $ui.DiagnosticAdviceLabel = New-CampusUiLabel '' 9.5 '#CBD5E1'
            $ui.DiagnosticAdviceLabel.AutoEllipsis = $true; $ui.DiagnosticAdviceLabel.Padding = New-Object Windows.Forms.Padding(0, 8, 0, 6)
            [void]$resultLayout.Controls.Add($ui.DiagnosticAdviceLabel, 0, 4)
            $rawHeader = New-CampusUiTable -Rows 1 -Columns 2
            [void]$rawHeader.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
            [void]$rawHeader.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 120)))
            $rawLabel = New-CampusUiLabel '完整结果' 9 '#94A3B8'; $rawLabel.Padding = New-Object Windows.Forms.Padding(0, 0, 0, 6)
            $rawHint = New-CampusUiLabel '可选中复制' 8.5 '#94A3B8'; $rawHint.TextAlign = 'MiddleRight'; $rawHint.Padding = New-Object Windows.Forms.Padding(0, 0, 0, 6)
            [void]$rawHeader.Controls.Add($rawLabel, 0, 0); [void]$rawHeader.Controls.Add($rawHint, 1, 0)
            [void]$resultLayout.Controls.Add($rawHeader, 0, 5)
            [void]$resultLayout.Controls.Add($textWell, 0, 6)
        } else {
            $textBox.Name = 'logTextBox'; $textBox.WordWrap = $false; $textBox.Text = '暂无运行记录。'; $ui.LogTextBox = $textBox
            $textBox.Font = New-Object Drawing.Font('Consolas', 9.5)
            $resultLayout = New-CampusUiTable -Rows 2
            Add-CampusUiRow $resultLayout 34; Add-CampusUiRow $resultLayout 100 -Percent
            [void]$resultLayout.Controls.Add((New-CampusUiLabel '最近记录' 11.5 '#F8FAFC' -Bold), 0, 0)
            [void]$resultLayout.Controls.Add($textWell, 0, 1)
        }
        [void]$resultCard.Controls.Add($resultLayout)
        [void]$page.Controls.Add($resultCard, 0, 2); $ui.Pages[$definition[0]] = $page
    }
    foreach ($page in $ui.Pages.Values) { $page.Visible = $false; [void]$content.Controls.Add($page) }
    $footer = New-Object Windows.Forms.Panel
    $footer.Dock = 'Fill'; $footer.Margin = New-Object Windows.Forms.Padding(0)
    $footer.BackColor = ConvertTo-CampusColor '#0B1220'; $footer.Padding = New-Object Windows.Forms.Padding(238, 0, 30, 0)
    $footerLine = New-Object Windows.Forms.Panel
    $footerLine.Dock = 'Top'; $footerLine.Height = 1; $footerLine.BackColor = ConvertTo-CampusColor '#1E293B'
    [void]$footer.Controls.Add($footerLine)
    $ui.FeedbackLabel = New-CampusUiLabel '就绪 · 密码仅保存在本机' 8.5 '#94A3B8'; $ui.FeedbackLabel.Name = 'feedbackLabel'; $ui.FeedbackLabel.AutoEllipsis = $true
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
        $color = '#94A3B8'; $kind = 'Info'
        if ($item.Tone -eq 'Success') { $color = '#10B981'; $kind = 'Online' }
        elseif ($item.Tone -eq 'Warning') { $color = '#F59E0B'; $kind = 'Warning' }
        elseif ($Phase -eq 'Busy') { $color = '#38BDF8'; $kind = 'Busy' }
        $row.Label.Text = $item.Label; $row.Value.Text = $item.Value
        $row.Value.ForeColor = ConvertTo-CampusColor $color
        $row.Glyph.Kind = $kind; $row.Glyph.AccentColor = $row.Value.ForeColor
        $row.Glyph.AccessibleName = $item.Label + '：' + $item.Value
        $Ui.ToolTips.SetToolTip($row.Value, $item.Value)
    }
    $Ui.DiagnosticTextBox.Text = $Text
}

function Show-CampusUiPage {
    param([hashtable]$Ui, [ValidateSet('Status', 'Account', 'Diagnostics', 'Logs')][string]$Page)
    foreach ($entry in $Ui.Pages.GetEnumerator()) { $entry.Value.Visible = $entry.Key -eq $Page }
    foreach ($entry in $Ui.Navigation.GetEnumerator()) {
        $selected = $entry.Key -eq $Page
        $entry.Value.BackColor = ConvertTo-CampusColor $(if ($selected) { '#334155' } else { '#1E293B' })
        $entry.Value.ForeColor = ConvertTo-CampusColor $(if ($selected) { '#38BDF8' } else { '#CBD5E1' })
        $Ui.NavigationGlyphs[$entry.Key].AccentColor = $entry.Value.ForeColor
        $Ui.NavigationGlyphs[$entry.Key].LineWidth = if ($selected) { 2.1 } else { 1.8 }
        $entry.Value.Invalidate()
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
    $accent = '#F59E0B'; $tint = '#451A03'; $glyph = 'Warning'; $badge = '待检查'; $monitorText = '运行中'
    switch ([string]$Model.MonitorState) {
        'Starting' { $monitorText = '正在启动'; $glyph = 'Busy'; $badge = '检查中'; $accent = '#38BDF8'; $tint = '#082F49' }
        'LoggingIn' { $monitorText = '正在自动登录'; $glyph = 'Busy'; $badge = '登录中'; $accent = '#38BDF8'; $tint = '#082F49' }
        'RetryWaiting' { $monitorText = '等待重试'; $badge = '等待重试' }
        'Error' { $monitorText = '需要检查'; $badge = '需处理'; $accent = '#F87171'; $tint = '#450A0A' }
        'Stopped' { $monitorText = '已暂停' }
    }
    if ($Model.AuthState -eq 'Online' -and $Model.MonitorState -notin @('Error', 'LoggingIn', 'Starting', 'RetryWaiting')) {
        $accent = '#10B981'; $tint = '#064E3B'; $glyph = 'Online'; $badge = '已连接'
    }
    if (-not $Model.MonitorRunning -and $Model.MonitorState -ne 'Error') {
        $monitorText = '已暂停'; $accent = '#94A3B8'; $tint = '#1F2937'; $glyph = 'Paused'; $badge = '已暂停'
    }
    $Ui.StatusTextLabel.ForeColor = ConvertTo-CampusColor '#F8FAFC'
    $Ui.MonitorStateLabel.Text = '自动监测：' + $monitorText
    $Ui.MonitorStateLabel.ForeColor = ConvertTo-CampusColor $(if ($Model.MonitorState -eq 'Error') { '#F87171' } elseif ($glyph -eq 'Online') { '#6EE7B7' } elseif ($glyph -eq 'Warning') { '#FBBF24' } elseif ($glyph -eq 'Paused') { '#94A3B8' } else { '#7DD3FC' })
    $Ui.StatusGlyph.Kind = $glyph; $Ui.StatusGlyph.AccentColor = ConvertTo-CampusColor $accent
    $Ui.StatusGlyph.AccessibleName = $Ui.StatusTextLabel.Text + '，' + $Ui.MonitorStateLabel.Text
    $Ui.StatusIconWell.BackColor = ConvertTo-CampusColor $tint
    $Ui.StatusIconWell.BorderColor = ConvertTo-CampusColor $(if ($Model.MonitorState -eq 'Error') { '#991B1B' } elseif ($glyph -eq 'Online') { '#0F766E' } elseif ($glyph -eq 'Warning') { '#92400E' } elseif ($glyph -eq 'Paused') { '#3F4B5E' } else { '#0369A1' })
    $Ui.StatusBadge.BackColor = $Ui.StatusIconWell.BackColor; $Ui.StatusBadge.BorderColor = $Ui.StatusBadge.BackColor
    $Ui.BadgeLabel.Text = $badge
    # Small badge text needs more contrast than the larger status glyph.
    $Ui.BadgeLabel.ForeColor = ConvertTo-CampusColor $(if ($glyph -eq 'Online') { '#34D399' } else { $accent })
    $Ui.ToggleMonitorButton.Text = if ($Model.MonitorRunning) { '暂停监测' } else { '开始监测' }
    $Ui.CheckNowButton.Enabled = [bool]$Model.MonitorRunning
    $Ui.VpnStateLabel.Text = if ($Model.VpnActive) { 'VPN 已启用  ·  校园网认证地址需直连' } else { '未检测到活动 VPN 隧道' }
    $Ui.VpnGlyph.Kind = if ($Model.VpnActive) { 'Warning' } else { 'Shield' }
    $Ui.VpnGlyph.AccentColor = ConvertTo-CampusColor $(if ($Model.VpnActive) { '#FBBF24' } else { '#64748B' })
    $Ui.ClearCredentialButton.Enabled = [bool]$Model.CredentialAvailable
    $Ui.CredentialStateLabel.Text = if ($Model.CredentialAvailable) { '密码已加密，只保存在这台电脑。' } else { '填写并保存账号后，即可开始自动监测。' }
}
