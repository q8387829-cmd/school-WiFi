[CmdletBinding()]
param([switch]$Strict)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# This tool never loads application code or traverses generated private data.
function Test-GeneratedPath([string]$Relative) {
    foreach ($directory in @('app/data', 'app/CampusNetwork-Lens/state')) {
        if ($Relative.Equals($directory, [StringComparison]::OrdinalIgnoreCase) -or
            $Relative.StartsWith($directory + '/', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Assert-RegularPath([string]$Root, [string[]]$Parts) {
    $current = $Root
    foreach ($part in $Parts) {
        $current = Join-Path $current $part
        if ([IO.File]::Exists($current) -or [IO.Directory]::Exists($current)) {
            if (([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw '发行文件路径含符号链接或目录联接，拒绝跟随。'
            }
        }
    }
}

try {
    $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if (([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '发行根目录不能是符号链接或目录联接。' }
    $manifestName = '文件清单.sha256'
    $manifest = Join-Path $root $manifestName
    Assert-RegularPath $root @($manifestName)
    if (-not [IO.File]::Exists($manifest)) { throw '缺少根目录文件清单.sha256；请取得完整发行包后再校验。' }
    $listed = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $failures = New-Object 'Collections.Generic.List[string]'
    $count = 0
    foreach ($line in [IO.File]::ReadAllLines($manifest, [Text.Encoding]::UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -notmatch '^([a-fA-F0-9]{64})  (.+)$') { throw '文件清单格式错误，应为 SHA256、两个空格和相对路径。' }
        $expected = $Matches[1]
        $relative = $Matches[2]
        $normal = $relative.Replace('\', '/')
        if ([IO.Path]::IsPathRooted($relative) -or $normal.StartsWith('/') -or $normal -match '[<>:"|?*\x00-\x1f]') { throw '文件清单包含无效、绝对或特殊路径。' }
        $parts = $normal.Split([char]47)
        foreach ($part in $parts) {
            if ($part -in @('', '.', '..') -or $part.EndsWith(' ') -or $part.EndsWith('.') -or
                $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { throw '文件清单包含不允许的路径分量。' }
        }
        if ((Test-GeneratedPath $normal) -or $normal -match '(?i)(^|/)(credential\.xml|[^/]+\.(log|tmp|old))$') { throw '文件清单不能包含私人数据、日志或临时文件。' }
        if ($normal.Equals($manifestName, [StringComparison]::OrdinalIgnoreCase)) { throw '文件清单不能列入自身。' }
        if (-not $listed.Add($normal)) { throw '文件清单包含重复路径。' }
        $path = [IO.Path]::GetFullPath((Join-Path $root $normal))
        if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw '文件清单路径超出发行目录。' }
        Assert-RegularPath $root $parts
        if (-not [IO.File]::Exists($path)) { $failures.Add('缺失：' + $normal) }
        elseif ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected) { $failures.Add('变化：' + $normal) }
        $count++
    }
    if ($count -eq 0) { throw '文件清单为空。' }

    $pending = New-Object 'Collections.Generic.Queue[string]'
    $pending.Enqueue($root)
    while ($pending.Count -gt 0) {
        $directory = $pending.Dequeue()
        foreach ($entry in [IO.Directory]::GetFileSystemEntries($directory)) {
            $relative = $entry.Substring($prefix.Length).Replace('\', '/')
            $attributes = [IO.File]::GetAttributes($entry)
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $failures.Add('不允许链接：' + $relative); continue }
            if (Test-GeneratedPath $relative) {
                if (($attributes -band [IO.FileAttributes]::Directory) -eq 0) { $failures.Add('运行数据路径必须是目录：' + $relative) }
                elseif ($Strict) { $failures.Add('发行包含运行数据目录：' + $relative) }
                continue
            }
            if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) { $pending.Enqueue($entry); continue }
            if (-not $relative.Equals($manifestName, [StringComparison]::OrdinalIgnoreCase) -and -not $listed.Contains($relative)) { $failures.Add('未列入清单：' + $relative) }
        }
    }
    if ($failures.Count -gt 0) {
        foreach ($failure in $failures) { Write-Host $failure -ForegroundColor Red }
        Write-Host '校验未通过；请从原始发行包重新完整解压。此工具未修改文件。' -ForegroundColor Red
        exit 1
    }
    Write-Host ('校验通过：' + $count + ' 个发行文件完整，无未登记程序文件。') -ForegroundColor Green
    if ($Strict) { Write-Host '严格检查通过：发行目录中没有个人数据和浏览器缓存目录。' }
    else { Write-Host '运行生成的 app/data 与 app/CampusNetwork-Lens/state 不参与校验，未读取其内容。' }
    Write-Host '哈希只能核对内容一致性，不能替代可信来源或发布者数字签名。'
    exit 0
} catch {
    Write-Host ('校验失败：' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
