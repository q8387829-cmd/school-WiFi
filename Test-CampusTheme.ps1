[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'CampusNetwork.TrayView.ps1')
$script:checks = 0; $script:failures = @()
function Assert-Theme([bool]$Condition, [string]$Message) {
    $script:checks++
    if (-not $Condition) { $script:failures += $Message; Write-Host ('FAIL: ' + $Message) }
}
function Get-Luminance([Drawing.Color]$Color) {
    $channels = @($Color.R, $Color.G, $Color.B) | ForEach-Object {
        $value = $_ / 255.0
        if ($value -le 0.04045) { $value / 12.92 } else { [Math]::Pow((($value + 0.055) / 1.055), 2.4) }
    }
    return $channels[0]*0.2126 + $channels[1]*0.7152 + $channels[2]*0.0722
}
function Get-Contrast([Drawing.Color]$First, [Drawing.Color]$Second) {
    $a = Get-Luminance $First; $b = Get-Luminance $Second
    return ([Math]::Max($a,$b)+0.05)/([Math]::Min($a,$b)+0.05)
}
function Get-FieldEdge($Field) {
    $well = $Field.Parent
    $image = New-Object Drawing.Bitmap($well.Width,$well.Height)
    try {
        $well.DrawToBitmap($image,(New-Object Drawing.Rectangle(0,0,$well.Width,$well.Height)))
        return $image.GetPixel([int]($well.Width/2),0).ToArgb()
    } finally { $image.Dispose() }
}
function Invoke-ThemeEvent($Control, [string]$Name, $Argument) {
    $method = $Control.GetType().GetMethod($Name, ([Reflection.BindingFlags]::Instance -bor [Reflection.BindingFlags]::NonPublic))
    [void]$method.Invoke($Control, [object[]]@($Argument.PSObject.BaseObject))
}
function Get-ThemeBitmap($Control) {
    $bitmap = New-Object Drawing.Bitmap($Control.Width,$Control.Height)
    $Control.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$bitmap.Width,$bitmap.Height)))
    return $bitmap
}
function Get-ThemeHash($Control) {
    $bitmap = Get-ThemeBitmap $Control
    $stream = New-Object IO.MemoryStream
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png)
        return [BitConverter]::ToString($sha.ComputeHash($stream.ToArray()))
    } finally { $sha.Dispose(); $stream.Dispose(); $bitmap.Dispose() }
}
function Measure-ThemeInk($Bitmap, [Drawing.Color]$Color) {
    $count = 0; $left = $Bitmap.Width
    for ($y=0; $y -lt $Bitmap.Height; $y++) {
        for ($x=0; $x -lt $Bitmap.Width; $x++) {
            if ($Bitmap.GetPixel($x,$y).ToArgb() -eq $Color.ToArgb()) { $count++; $left = [Math]::Min($left,$x) }
        }
    }
    return [pscustomobject]@{ Count=$count; Left=$left }
}
$ui = New-CampusTrayView
try {
    foreach ($button in @($ui.SaveButton,$ui.DiagnosisButton,$ui.CheckNowButton,$ui.ClearCredentialButton)) {
        foreach ($background in @($button.BackColor,$button.FlatAppearance.MouseOverBackColor,$button.FlatAppearance.MouseDownBackColor)) {
            Assert-Theme ((Get-Contrast $button.ForeColor $background) -ge 4.5) ($button.Name + ' readable in normal, hover and pressed states')
        }
    }
    $ui.CheckNowButton.Enabled = $false
    Assert-Theme ($ui.CheckNowButton.Cursor -eq [Windows.Forms.Cursors]::Default) 'Unavailable action uses the default cursor'
    $disabledBitmap = New-Object Drawing.Bitmap($ui.CheckNowButton.Width,$ui.CheckNowButton.Height)
    try {
        $ui.CheckNowButton.DrawToBitmap($disabledBitmap,(New-Object Drawing.Rectangle(0,0,$disabledBitmap.Width,$disabledBitmap.Height)))
        $readableInk = 0
        for ($y=6; $y -lt ($disabledBitmap.Height-6); $y++) {
            for ($x=8; $x -lt ($disabledBitmap.Width-8); $x++) {
                if ((Get-Contrast $disabledBitmap.GetPixel($x,$y) $ui.CheckNowButton.BackColor) -ge 3.0) { $readableInk++ }
            }
        }
        Assert-Theme ($readableInk -gt 10) 'Disabled action actually paints legible muted text rather than native black'
    } finally { $disabledBitmap.Dispose() }
    $ui.CheckNowButton.Enabled = $true
    Assert-Theme ($ui.CheckNowButton.Cursor -eq [Windows.Forms.Cursors]::Hand) 'Re-enabled action restores the hand cursor'
    # A hard-coded light selection fill makes the selected carrier unreadable
    # when the actual ComboBox is given the dark input colors.
    $combo = $ui.CarrierComboBox
    $combo.BackColor = ConvertTo-CampusColor '#0F172A'; $combo.ForeColor = ConvertTo-CampusColor '#F8FAFC'
    $bitmap = New-Object Drawing.Bitmap(180,32)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $eventArgs = New-Object Windows.Forms.DrawItemEventArgs($graphics,$combo.Font,(New-Object Drawing.Rectangle(0,0,180,32)),0,[Windows.Forms.DrawItemState]::Selected)
        $method = $combo.GetType().GetMethod('OnDrawItem',([Reflection.BindingFlags]::Instance -bor [Reflection.BindingFlags]::NonPublic))
        [void]$method.Invoke($combo,[object[]]@($eventArgs.PSObject.BaseObject))
        Assert-Theme ((Get-Contrast $combo.ForeColor $bitmap.GetPixel(1,1)) -ge 4.5) 'Selected carrier remains readable with a dark field'
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
    $sample = "2026-10-21 09:00:00  登录成功。`r`n2026-10-21 09:01:00  认证接口响应超时。"
    Set-CampusLogPresentation -TextBox $ui.LogTextBox -Text $sample
    foreach ($needle in @('2026-10-21','登录成功','响应超时')) {
        $ui.LogTextBox.Select($ui.LogTextBox.Text.IndexOf($needle),$needle.Length)
        Assert-Theme ((Get-Contrast $ui.LogTextBox.SelectionColor $ui.LogTextBox.BackColor) -ge 4.5) ('Readable log segment: ' + $needle)
    }
    $model = [pscustomobject]@{ StatusText='连接状态'; DetailText='检查状态'; LastLoginAt=''; LastError=''; UpdatedAt=''; Suggestion=''; AuthState='Online'; MonitorState='Running'; MonitorRunning=$true; VpnActive=$false; CredentialAvailable=$false }
    foreach ($state in @('Running','Starting','RetryWaiting','Error','Stopped')) {
        $model.MonitorState=$state; $model.MonitorRunning=$state -ne 'Stopped'
        Set-CampusUiModel $ui $model
        $ratio = Get-Contrast $ui.BadgeLabel.ForeColor $ui.StatusBadge.BackColor
        Assert-Theme ($ratio -ge 4.5) ('Readable state badge: ' + $state + ' (' + [Math]::Round($ratio,2) + ')')
    }
    $ui.Form.ShowInTaskbar=$false; $ui.Form.StartPosition='Manual'; $ui.Form.Location=New-Object Drawing.Point(-3000,-3000)
    Show-CampusUiPage $ui Account; $ui.Form.Show(); [Windows.Forms.Application]::DoEvents()
    [void]$ui.SaveButton.Focus()
    $unfocused = Get-FieldEdge $ui.AccountTextBox
    $message = [Windows.Forms.Message]::Create($ui.Form.Handle,0x100,[IntPtr]9,[IntPtr]::Zero)
    [void][Windows.Forms.Application]::FilterMessage([ref]$message)
    [void]$ui.AccountTextBox.Focus(); [Windows.Forms.Application]::DoEvents()
    Assert-Theme ((Get-FieldEdge $ui.AccountTextBox) -ne $unfocused) 'Keyboard focus visibly outlines the account field'
    $message = [Windows.Forms.Message]::Create($ui.Form.Handle,0x201,[IntPtr]::Zero,[IntPtr]::Zero)
    [void][Windows.Forms.Application]::FilterMessage([ref]$message)
    Assert-Theme ((Get-FieldEdge $ui.AccountTextBox) -eq $unfocused) 'Mouse input removes the additional keyboard focus outline'

    # Error must override a stale Online result, including the newly added outline.
    $model.AuthState='Online'; $model.MonitorState='Error'; $model.MonitorRunning=$false
    Set-CampusUiModel $ui $model
    Assert-Theme ($ui.StatusIconWell.BorderColor.ToArgb() -eq (ConvertTo-CampusColor '#991B1B').ToArgb()) 'Error uses a red status outline even with a stale Online result'
    Assert-Theme ($ui.MonitorStateLabel.ForeColor.ToArgb() -eq (ConvertTo-CampusColor '#F87171').ToArgb()) 'Error monitor text uses the error color'
    $model.MonitorState='RetryWaiting'; $model.MonitorRunning=$true
    Set-CampusUiModel $ui $model
    Assert-Theme ($ui.StatusIconWell.BorderColor.ToArgb() -eq (ConvertTo-CampusColor '#92400E').ToArgb()) 'Retry warning keeps its amber outline'

    # Native CheckBox.FlatAppearance does not paint CheckedBackColor in Normal appearance.
    $toggle=$ui.StartupCheckBox
    foreach ($checked in @($false,$true)) {
        $toggle.Checked=$checked
        $bitmap=Get-ThemeBitmap $toggle
        try {
            $blue=Measure-ThemeInk $bitmap (ConvertTo-CampusColor '#0EA5E9')
            $white=Measure-ThemeInk $bitmap (ConvertTo-CampusColor '#F8FAFC')
            if ($checked) {
                Assert-Theme ($blue.Count -gt 20) 'Checked setting actually paints a sky-blue fill'
                Assert-Theme ($white.Count -gt 5) 'Checked setting paints a light tick'
            } else { Assert-Theme ($blue.Count -eq 0) 'Unchecked setting has no selected blue fill' }
        } finally { $bitmap.Dispose() }
    }
    $script:settingChanges=0
    $toggle.add_CheckedChanged({ $script:settingChanges++ })
    [void]$toggle.Focus()
    Invoke-ThemeEvent $toggle OnKeyDown (New-Object Windows.Forms.KeyEventArgs([Windows.Forms.Keys]::Space))
    Invoke-ThemeEvent $toggle OnKeyUp (New-Object Windows.Forms.KeyEventArgs([Windows.Forms.Keys]::Space))
    Assert-Theme (-not $toggle.Checked -and $script:settingChanges -eq 1) 'Styled native setting still toggles exactly once with Space'
    Invoke-ThemeEvent ($toggle.Parent.GetControlFromPosition(1,0)) OnClick ([EventArgs]::Empty)
    Assert-Theme ($toggle.Checked -and $script:settingChanges -eq 2) 'Setting label still toggles exactly once'
    $toggle.Enabled=$false
    Invoke-ThemeEvent ($toggle.Parent.GetControlFromPosition(1,0)) OnClick ([EventArgs]::Empty)
    Assert-Theme ($toggle.Checked -and $script:settingChanges -eq 2) 'Disabled setting cannot be toggled through its label'
    $toggle.Enabled=$true

    Show-CampusUiPage $ui Status
    [void]$ui.Navigation.Status.Focus()
    $nav=$ui.Navigation.Account
    $normal=Get-ThemeHash $nav
    $message=[Windows.Forms.Message]::Create($ui.Form.Handle,0x100,[IntPtr]9,[IntPtr]::Zero)
    [void][Windows.Forms.Application]::FilterMessage([ref]$message)
    [void]$nav.Focus(); [Windows.Forms.Application]::DoEvents()
    Assert-Theme ($nav.Focused -and (Get-ThemeHash $nav) -ne $normal) 'Tab focus remains visible without holding a modifier key'
    $message=[Windows.Forms.Message]::Create($ui.Form.Handle,0x201,[IntPtr]::Zero,[IntPtr]::Zero)
    [void][Windows.Forms.Application]::FilterMessage([ref]$message)
    Assert-Theme ((Get-ThemeHash $nav) -eq $normal) 'Mouse input clears the extra navigation focus outline'
    Invoke-ThemeEvent $nav OnMouseEnter ([EventArgs]::Empty)
    $bitmap=Get-ThemeBitmap $nav
    try {
        $glyph=$ui.NavigationGlyphs.Account
        Assert-Theme ($bitmap.GetPixel($glyph.Left,$glyph.Top).ToArgb() -eq $bitmap.GetPixel(($glyph.Left-1),$glyph.Top).ToArgb()) 'Hovered navigation glyph shares the painted button background'
    } finally { $bitmap.Dispose() }

    $hoverFace=Get-ThemeHash $nav
    Invoke-ThemeEvent $nav OnMouseLeave ([EventArgs]::Empty)
    Invoke-ThemeEvent $ui.NavigationGlyphs.Account OnMouseEnter ([EventArgs]::Empty)
    Assert-Theme ((Get-ThemeHash $nav) -eq $hoverFace) 'Moving from navigation text onto its clickable icon keeps the hover surface'
    # The synthetic form is offscreen, so the real pointer is outside this button.
    Invoke-ThemeEvent $ui.NavigationGlyphs.Account OnMouseLeave ([EventArgs]::Empty)
    Assert-Theme ((Get-ThemeHash $nav) -eq $normal) 'Leaving the navigation icon for outside clears the hover surface'

    # Paint at a real Graphics DPI as well as scaling bounds: geometry-only tests miss double scaling.
    foreach ($scale in @(1.25,1.5,2.0)) {
        $probe=New-CampusNavButton 'MMMM' 'dpiProbe' 'Account'
        $probe.Size=New-Object Drawing.Size([int](220*$scale),[int](42*$scale))
        $probe.Padding=New-Object Windows.Forms.Padding([int](44*$scale),0,0,0)
        $bitmap=New-Object Drawing.Bitmap($probe.Width,$probe.Height)
        $bitmap.SetResolution([single](96*$scale),[single](96*$scale))
        $graphics=[Drawing.Graphics]::FromImage($bitmap)
        try {
            Invoke-ThemeEvent $probe OnPaint (New-Object Windows.Forms.PaintEventArgs($graphics,$probe.ClientRectangle))
            $ink=Measure-ThemeInk $bitmap $probe.ForeColor
            Assert-Theme ($ink.Count -gt 0 -and $ink.Left -ge $probe.Padding.Left -and $ink.Left -le ($probe.Padding.Left+12)) ('Navigation text uses padding once at ' + (100*$scale) + '% DPI')
        } finally { $graphics.Dispose(); $bitmap.Dispose(); $probe.Dispose() }
    }

    # The same ordinal has incompatible signatures on 1809 and 1903+.
    $selector=[CampusNetwork.UI.DarkScrollbars].GetMethod('GetAppModeApi',([Reflection.BindingFlags]::Static -bor [Reflection.BindingFlags]::NonPublic))
    Assert-Theme ($null -ne $selector) 'Native dark theme selects its API using the Windows version'
    if ($null -ne $selector) {
        foreach ($case in @(@('6.1.7601',0),@('10.0.17134',0),@('10.0.17763',1),@('10.0.18361',0),@('10.0.18362',2),@('10.0.19045',2),@('10.0.22000',2),@('10.0.26200',2))) {
            $version=[version]$case[0]
            $api=$selector.Invoke($null,[object[]]@($version))
            Assert-Theme ($api -eq $case[1]) ('Safe native dark-theme API for Windows ' + $case[0])
        }
    }
    Assert-Theme (-not [CampusNetwork.UI.DarkScrollbars]::Apply([IntPtr]::Zero)) 'A missing native window never reports dark scrollbars applied'
} finally { $ui.Form.Dispose() }
Write-Host ('Theme checks: ' + $script:checks + '; failures: ' + $script:failures.Count)
if ($script:failures.Count) { exit 1 }
