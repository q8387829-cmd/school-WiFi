$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CampusNetwork.Presentation.ps1')
$script:presentationChecks = 0

function Assert-Presentation([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw ('FAIL: ' + $Name) }
    $script:presentationChecks++
    Write-Host ('PASS: ' + $Name)
}

function Get-TestLogColor($TextBox, [string]$Needle) {
    $position = $TextBox.Text.IndexOf($Needle, [StringComparison]::Ordinal)
    if ($position -lt 0) { throw ('Missing fixture text: ' + $Needle) }
    $TextBox.Select($position, $Needle.Length)
    return $TextBox.SelectionColor.ToArgb()
}

# Synthetic report fixtures only: no Service/Core import or real network/data access.
$onlineText = @'
[Authenticated/status/HTTP 200] 校园网已登录。 保持监测，无需重复登录。
VPN 隧道启用：True
认证请求已禁用系统 HTTP 代理。
认证地址 10.10.102.50 端口 80：Reachable
认证地址 10.10.102.50 端口 801：Reachable
'@
$online = ConvertTo-CampusDiagnosticPresentation -Text $onlineText -Success $true
Assert-Presentation ($online.Title -eq '校园网认证正常') 'authenticated report has an authentication-specific heading'
Assert-Presentation ($online.Tone -eq 'Success') 'confirmed authentication and reachable ports allow success tone'
Assert-Presentation ($online.Summary -eq '校园网已登录。') 'summary separates conclusion from recommendation'
Assert-Presentation ($online.Advice -eq '保持监测，无需重复登录。') 'recommendation is preserved'
Assert-Presentation ($online.Items.Count -eq 4) 'report exposes exactly four stable check rows'
Assert-Presentation ($online.Items[0].Value -eq '已登录') 'authentication row is explicit'
Assert-Presentation ($online.Items[1].Value -eq '可连接' -and $online.Items[2].Value -eq '可连接') 'port 80 and 801 are parsed separately'
Assert-Presentation ($online.Items[3].Value -eq '已启用' -and $online.Items[3].Tone -eq 'Neutral') 'enabled VPN is informational rather than an error'

$offline = ConvertTo-CampusDiagnosticPresentation -Text ($onlineText -replace '\[Authenticated/', '[NotAuthenticated/' -replace '校园网已登录。', '校园网未登录或认证已过期。') -Success $true
Assert-Presentation ($offline.Title -eq '校园网尚未登录' -and $offline.Tone -eq 'Warning') 'completed diagnostics with Offline are never reported as connected'
Assert-Presentation ($offline.Items[0].Value -eq '未登录') 'offline authentication is not masked by reachable ports'

$unknown = ConvertTo-CampusDiagnosticPresentation -Text "[RequestTimeout/status] 校园网认证接口响应超时。 稍后重试。`r`nVPN 隧道启用：False`r`n认证地址 10.10.102.50 端口 801：RequestTimeout" -Success $true
Assert-Presentation ($unknown.Title -eq '连接需要检查' -and $unknown.Tone -eq 'Warning') 'fault code produces a check-needed conclusion'
Assert-Presentation ($unknown.Items[0].Value -eq '未确认') 'timeout never implies logged out'
Assert-Presentation ($unknown.Items[1].Value -eq '未检查') 'a missing port 80 result is not guessed from port 801'
Assert-Presentation ($unknown.Items[2].Value -eq '连接超时' -and $unknown.Items[2].Tone -eq 'Warning') 'port timeout has a readable warning'
Assert-Presentation ($unknown.Items[3].Value -eq '未启用') 'explicit VPN false is recognized'

$empty = ConvertTo-CampusDiagnosticPresentation -Text '' -Success $true
Assert-Presentation ($empty.Title -eq '连接需要检查') 'empty successful process output does not invent connectivity'
Assert-Presentation ($empty.Items[1].Value -eq '未检查' -and $empty.Items[2].Value -eq '未检查') 'missing port results remain untested'
Assert-Presentation ($empty.Items[3].Value -eq '未确认') 'missing VPN status remains unconfirmed'

$failed = ConvertTo-CampusDiagnosticPresentation -Text $onlineText -Success $false
Assert-Presentation ($failed.Tone -eq 'Warning' -and $failed.Title -eq '连接需要检查') 'failed diagnostic task cannot acquire a green heading'
Assert-Presentation ($failed.Items[0].Value -eq '未确认') 'failed report cannot assert current authentication'
Assert-Presentation ($failed.Advice -eq '请查看完整诊断详情，稍后重新运行检查。') 'failed report replaces stale successful advice with retry guidance'
$failedPlain = ConvertTo-CampusDiagnosticPresentation -Text '诊断已超时，请稍后重试。' -Success $false
Assert-Presentation ($failedPlain.Summary -eq '诊断已超时，请稍后重试。') 'plain failure reason is retained in the summary'

$preview = ConvertTo-CampusDiagnosticPresentation -Text "网络诊断完成`r`n无线连接：正常`r`nHTTP 80 端口：可连接`r`n认证 801 端口：可连接`r`nVPN 隧道：已启用`r`n校园网认证：已登录`r`n建议：当前认证服务可访问，请保持校园网认证地址为直连。" -Success $true
Assert-Presentation ($preview.Title -eq '校园网认证正常') 'existing Chinese preview authentication is recognized'
Assert-Presentation ($preview.Items[1].Value -eq '可连接' -and $preview.Items[2].Value -eq '可连接') 'existing Chinese preview ports are recognized'
Assert-Presentation ($preview.Advice -eq '当前认证服务可访问，请保持校园网认证地址为直连。') 'explicit Chinese advice is kept'
$previewOffline = ConvertTo-CampusDiagnosticPresentation -Text '校园网认证：未登录' -Success $true
Assert-Presentation ($previewOffline.Title -eq '校园网尚未登录') 'Chinese offline preview remains offline'
$suggestionOnly = ConvertTo-CampusDiagnosticPresentation -Text '建议：确认校园网认证：已登录后重试。' -Success $true
Assert-Presentation ($suggestionOnly.Title -eq '连接需要检查') 'an instruction mentioning login does not assert authentication'
$codeWins = ConvertTo-CampusDiagnosticPresentation -Text "[SessionMismatch/status] 仅返回其他会话。 请检查。`n校园网认证：已登录" -Success $true
Assert-Presentation ($codeWins.Title -eq '连接需要检查') 'authoritative unknown code cannot be overridden by incidental translated text'

foreach ($fault in @('ConnectionRefused', 'HostUnreachable', 'AccessDenied', 'UnexpectedFailure')) {
    $result = ConvertTo-CampusDiagnosticPresentation -Text ("[Authenticated] 校园网已登录。 保持监测。`n认证地址 10.10.102.50 端口 801：" + $fault)
    Assert-Presentation ($result.Tone -eq 'Warning' -and $result.Items[2].Tone -eq 'Warning') ('an authenticated report still surfaces port fault ' + $fault)
    Assert-Presentation ($result.Title -eq '校园网认证正常') ('port fault does not falsify known authentication ' + $fault)
}

$logBox = New-Object Windows.Forms.RichTextBox
$referenceBox = New-Object Windows.Forms.RichTextBox
$testFont = New-Object Drawing.Font('Microsoft YaHei UI', 10)
try {
    $logBox.Font = $testFont
    $logText = "[2026-10-18 11:00:00]  暂无异常。`r`n2026-10-18 11:01:00  自动登录成功。`r`n2026-10-18 11:02:00  自动重连已停止。`r`n2026-10-18 11:03:00  [RequestTimeout/status] 校园网认证接口响应超时。`r`n2026-10-18 11:04:00  登录失败，60 秒后重试。`r`n2026-10-18 11:05:00  [Authenticated] 校园网已登录。`r`n2026-10-18 11:06:00  [NotAuthenticated] 校园网未登录。`r`n复制符号 {hello} \line <details> 与中文保持完整。"
    $referenceBox.Text = $logText
    [void]$referenceBox.Handle
    $logBox.Text = $logText
    $logBox.Select(10, 8)
    Set-CampusLogPresentation -TextBox $logBox -Text $logText
    Assert-Presentation ($logBox.Text -ceq $referenceBox.Text) 'styling preserves the complete native text, Chinese, and literal markup'
    Assert-Presentation ($logBox.ReadOnly -and $logBox.ShortcutsEnabled) 'log remains readonly with copy shortcuts enabled'
    Assert-Presentation ($logBox.SelectionStart -eq 10 -and $logBox.SelectionLength -eq 8) 'styling preserves a valid existing selection'
    Assert-Presentation ($logBox.Rtf -match '\\sa80(?:\D|$)') 'paragraph spacing adds four points without inserting blank lines'
    $gray = [Drawing.ColorTranslator]::FromHtml('#94A3B8').ToArgb()
    $body = [Drawing.ColorTranslator]::FromHtml('#CBD5E1').ToArgb()
    $orange = [Drawing.ColorTranslator]::FromHtml('#F59E0B').ToArgb()
    Assert-Presentation ((Get-TestLogColor $logBox '2026-10-18 11:03:00') -eq $gray) 'timestamp stays gray on warning lines'
    Assert-Presentation ((Get-TestLogColor $logBox '暂无异常。') -eq $body) 'no abnormalities is not highlighted as an error'
    Assert-Presentation ((Get-TestLogColor $logBox '自动登录成功。') -eq $body) 'successful login remains ordinary body text'
    Assert-Presentation ((Get-TestLogColor $logBox '自动重连已停止。') -eq $body) 'intentional stop remains ordinary body text'
    Assert-Presentation ((Get-TestLogColor $logBox '校园网认证接口响应超时。') -eq $orange) 'explicit timeout is highlighted in readable amber'
    Assert-Presentation ((Get-TestLogColor $logBox '登录失败，60 秒后重试。') -eq $orange) 'explicit failure is highlighted without losing its words'
    Assert-Presentation ((Get-TestLogColor $logBox '[Authenticated]') -eq $body) 'normal authenticated diagnostic code is not an error'
    Assert-Presentation ((Get-TestLogColor $logBox '[NotAuthenticated]') -eq $body) 'routine offline detection is not formatted as a process failure'
    $logBox.SelectAll()
    Assert-Presentation ($logBox.SelectedText -ceq $referenceBox.Text) 'select-all retains the full copyable report'

    # Reimporting functions and formatting repeatedly must not redefine native types
    # or retain a Font/GDI object per refresh.
    . (Join-Path $PSScriptRoot 'CampusNetwork.Presentation.ps1')
    1..8 | ForEach-Object { Set-CampusLogPresentation -TextBox $logBox -Text $logText }
    Assert-Presentation ($logBox.Text -ceq $referenceBox.Text) 'reimport and repeated styling remain idempotent'
    Set-CampusLogPresentation -TextBox $logBox -Text ''
    Assert-Presentation ($logBox.TextLength -eq 0 -and $logBox.SelectionStart -eq 0) 'empty replacement clears stale text and clamps selection'
} finally {
    $logBox.Dispose(); $referenceBox.Dispose(); $testFont.Dispose()
}

Write-Host ('Presentation checks passed: ' + $script:presentationChecks)
