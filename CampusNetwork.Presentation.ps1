# Presentation helpers only. This file never reads credentials or checks a live network.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function ConvertTo-CampusDiagnosticPresentation {
    param([AllowEmptyString()][string]$Text = '', [bool]$Success = $true)

    $lines = @($Text -split '\r\n|\n|\r' | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    $code = ''; $message = ''; $advice = ''; $authState = 'Unknown'
    if ($lines.Count -gt 0) {
        $first = [regex]::Match($lines[0], '^\[(?<code>[A-Za-z][A-Za-z0-9]*)(?:/[^\]]*)?\]\s*(?<body>.*)$')
        if ($first.Success) {
            $code = $first.Groups['code'].Value
            $body = $first.Groups['body'].Value
            $sentence = [regex]::Match($body, '^(?<message>.*?[。！？])\s*(?<advice>.*)$')
            if ($sentence.Success) {
                $message = $sentence.Groups['message'].Value
                $advice = $sentence.Groups['advice'].Value
            } else { $message = $body }
            switch ($code) {
                'Authenticated' { $authState = 'Online' }
                'NotAuthenticated' { $authState = 'Offline' }
            }
        } else {
            # Preview/translated reports have an explicit status line. Do not infer
            # authentication from a successful port check or the process exit code.
            foreach ($line in $lines) {
                if ($line -match '^校园网认证\s*[:：]\s*(?:已登录|Online|Authenticated)\s*[。.]?$') { $authState = 'Online' }
                elseif ($line -match '^校园网认证\s*[:：]\s*(?:未登录|尚未登录|Offline|NotAuthenticated)\s*[。.]?$') { $authState = 'Offline' }
            }
        }
    }
    foreach ($line in $lines) {
        if ($line -match '^建议\s*[:：]\s*(.+)$') { $advice = $Matches[1] }
    }

    $title = '连接需要检查'; $tone = 'Warning'; $authValue = '未确认'; $authTone = 'Neutral'
    if ($Success) {
        switch ($authState) {
            'Online' {
                $title = '校园网认证正常'; $tone = 'Success'; $authValue = '已登录'; $authTone = 'Success'
                if (-not $message) { $message = '已确认本机校园网认证有效。' }
            }
            'Offline' {
                $title = '校园网尚未登录'; $authValue = '未登录'; $authTone = 'Warning'
                if (-not $message) { $message = '已确认校园网尚未登录或认证已过期。' }
            }
            default { if (-not $message) { $message = '尚未确认本机校园网认证状态。' } }
        }
    } else {
        # An incomplete diagnostic must never acquire a green success heading.
        $message = '诊断未能完成，尚不能确认当前连接状态。'
        if ($lines.Count -gt 0 -and -not $code) { $message = $lines[0] }
    }
    if (-not $advice) {
        switch ($authState) {
            'Online' { $advice = '认证状态已确认；其他检查结果请参阅下方项目和完整详情。' }
            'Offline' { $advice = '如已保存账号并开启监测，助手会在确认未登录后尝试自动登录。' }
            default { $advice = '请查看完整诊断详情，确认校园网连接后再运行检查。' }
        }
    }
    if (-not $Success) { $advice = '请查看完整诊断详情，稍后重新运行检查。' }

    $items = New-Object 'Collections.Generic.List[object]'
    $items.Add([pscustomobject]@{ Label = '校园网认证'; Value = $authValue; Tone = $authTone })
    foreach ($port in @(80, 801)) {
        $raw = ''; $portValue = '未检查'; $portTone = 'Neutral'
        foreach ($line in $lines) {
            $portMatch = [regex]::Match($line, ('^(?:认证地址\s+\S+\s+端口\s+' + $port + '|(?:HTTP|认证)\s+' + $port + '\s*端口)\s*[:：]\s*(?<value>.+)$'))
            if ($portMatch.Success) { $raw = $portMatch.Groups['value'].Value.Trim(); break }
        }
        if ($raw) {
            switch -Regex ($raw) {
                '^(Reachable|可连接|可达|正常)[。.]?$' { $portValue = '可连接'; $portTone = 'Success'; break }
                '^(未检查|未探测|跳过|未确认)[。.]?$' { $portValue = '未检查'; break }
                '^RequestTimeout$' { $portValue = '连接超时'; $portTone = 'Warning'; break }
                '^HostUnreachable$' { $portValue = '无法到达'; $portTone = 'Warning'; break }
                '^ConnectionRefused$' { $portValue = '连接被拒绝'; $portTone = 'Warning'; break }
                '^AccessDenied$' { $portValue = '访问被拒绝'; $portTone = 'Warning'; break }
                default { $portValue = $raw; $portTone = 'Warning' }
            }
        }
        $label = if ($port -eq 80) { '网页登录端口 80' } else { '认证端口 801' }
        $items.Add([pscustomobject]@{ Label = $label; Value = $portValue; Tone = $portTone })
        if ($portTone -eq 'Warning' -and $tone -eq 'Success') {
            $tone = 'Warning'
            $message += ' 部分端口检查未通过，请查看下方结果。'
        }
    }
    $vpnValue = '未确认'
    foreach ($line in $lines) {
        if ($line -match '^VPN\s*隧道(?:启用)?\s*[:：]\s*(True|已启用|启用)\s*[。.]?$') { $vpnValue = '已启用'; break }
        if ($line -match '^VPN\s*隧道(?:启用)?\s*[:：]\s*(False|未启用|未开启)\s*[。.]?$') { $vpnValue = '未启用'; break }
    }
    $items.Add([pscustomobject]@{ Label = 'VPN 隧道'; Value = $vpnValue; Tone = 'Neutral' })
    return [pscustomobject]@{ Title = $title; Summary = $message; Tone = $tone; Items = @($items.ToArray()); Advice = $advice }
}

function Set-CampusLogPresentation {
    param([Parameter(Mandatory = $true)][Windows.Forms.RichTextBox]$TextBox, [AllowEmptyString()][string]$Text = '')

    if ($TextBox.IsDisposed) { return }
    if (-not ('CampusNetwork.LogParagraphLayout' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace CampusNetwork {
    public static class LogParagraphLayout {
        [StructLayout(LayoutKind.Sequential)]
        private struct ParagraphFormat {
            public uint cbSize, dwMask;
            public ushort wNumbering, wReserved;
            public int dxStartIndent, dxRightIndent, dxOffset;
            public ushort wAlignment;
            public short cTabCount;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)] public int[] rgxTabs;
            public int dySpaceBefore, dySpaceAfter, dyLineSpacing;
            public short sStyle;
            public byte bLineSpacingRule, bOutlineLevel;
            public ushort wShadingWeight, wShadingStyle, wNumberingStart, wNumberingStyle,
                wNumberingTab, wBorderSpace, wBorderWidth, wBorders;
        }
        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern IntPtr SendMessage(IntPtr handle, uint message, IntPtr wParam, ref ParagraphFormat format);
        public static void SetSpacing(IntPtr handle) {
            ParagraphFormat format = new ParagraphFormat();
            format.cbSize = (uint)Marshal.SizeOf(typeof(ParagraphFormat));
            format.dwMask = 0x00000080; // PFM_SPACEAFTER, in twentieths of a point.
            format.dySpaceAfter = 80;
            format.rgxTabs = new int[32];
            SendMessage(handle, 0x447, IntPtr.Zero, ref format); // EM_SETPARAFORMAT
        }
    }
}
'@
    }

    $selectionStart = $TextBox.SelectionStart; $selectionLength = $TextBox.SelectionLength
    $TextBox.SuspendLayout()
    try {
        $TextBox.ReadOnly = $true
        $TextBox.Text = $Text
        $TextBox.SelectAll()
        $TextBox.SelectionColor = [Drawing.ColorTranslator]::FromHtml('#323238')
        $TextBox.SelectionFont = $TextBox.Font
        [CampusNetwork.LogParagraphLayout]::SetSpacing($TextBox.Handle)
        # Index against RichTextBox.Text: the native editor normalizes CRLF on
        # assignment. No symbols or line breaks are inserted into copyable text.
        $displayText = $TextBox.Text
        foreach ($line in [regex]::Matches($displayText, '[^\r\n]+')) {
            $timestamp = [regex]::Match($line.Value, '^\s*\[?\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}\]?\s*')
            $bodyStart = if ($timestamp.Success) { $timestamp.Length } else { 0 }
            $body = $line.Value.Substring($bodyStart)
            $severityText = $body -replace '(暂无异常|没有异常|未发现异常|无异常|异常已恢复)', ''
            $warning = $severityText -match '(?i)^\s*\[(ERROR|WARN|WARNING)\]' -or
                $severityText -match '(失败|超时|拒绝|无法|不可达|不可用|已过期|未能|未确认恢复|缺少账号|格式异常|返回异常|持续异常)'
            $diagnosticCode = [regex]::Match($body, '^\[(?<code>[A-Za-z][A-Za-z0-9]*)(?:/[^\]]*)?\]')
            if ($diagnosticCode.Success -and $diagnosticCode.Groups['code'].Value -notin @('Authenticated', 'NotAuthenticated', 'INFO', 'DEBUG')) { $warning = $true }
            if ($warning -and $body.Length -gt 0) {
                $TextBox.Select($line.Index + $bodyStart, $body.Length)
                $TextBox.SelectionColor = [Drawing.ColorTranslator]::FromHtml('#A55300')
            }
            if ($timestamp.Success) {
                $TextBox.Select($line.Index, $timestamp.Length)
                $TextBox.SelectionColor = [Drawing.ColorTranslator]::FromHtml('#6E6E76')
            }
        }
        $selectionStart = [Math]::Min($selectionStart, $TextBox.TextLength)
        $TextBox.Select($selectionStart, [Math]::Min($selectionLength, $TextBox.TextLength - $selectionStart))
    } finally { $TextBox.ResumeLayout() }
}
