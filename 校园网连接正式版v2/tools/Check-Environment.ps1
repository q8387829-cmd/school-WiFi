[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$failed = $false
function Show-Check([string]$Name, [bool]$Passed, [string]$Detail) {
    if ($Passed) { Write-Host ('[通过] ' + $Name + '：' + $Detail) -ForegroundColor Green }
    else { $script:failed = $true; Write-Host ('[需处理] ' + $Name + '：' + $Detail) -ForegroundColor Red }
}

try {
    $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $os = Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $architecture = [string]$env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $architecture = [string]$env:PROCESSOR_ARCHITEW6432 }
    $build = [int]$os.CurrentBuildNumber
    Show-Check 'Windows x64' ($architecture -eq 'AMD64' -and $build -ge 10240) ('系统版本 ' + $os.ProductName + '，内部版本 ' + $build + '，架构 ' + $architecture)
    $isWindowsPowerShell = $PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -ge 1 -and $PSVersionTable.PSEdition -eq 'Desktop'
    Show-Check 'Windows PowerShell 5.1' $isWindowsPowerShell ('当前 ' + $PSVersionTable.PSVersion.ToString())
    $framework = Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction SilentlyContinue
    $frameworkRelease = 0
    if ($null -ne $framework) { $frameworkRelease = [int]$framework.Release }
    Show-Check '.NET Framework 4.8 或更高' ($frameworkRelease -ge 528040) ('Release=' + $frameworkRelease)
    Show-Check 'Windows 脚本宿主' ([IO.File]::Exists((Join-Path $env:SystemRoot 'System32\wscript.exe'))) '检测 wscript.exe 是否存在；组织策略是否允许执行需由实际启动确认。'

    $runtimeRoots = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramW6432, $env:ProgramFiles, $env:LOCALAPPDATA)) {
        if ($base) { [void]$runtimeRoots.Add((Join-Path $base 'Microsoft\EdgeWebView\Application')) }
    }
    $versions = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($runtimeRoot in $runtimeRoots) {
        if (-not [IO.Directory]::Exists($runtimeRoot)) { continue }
        foreach ($directory in [IO.Directory]::GetDirectories($runtimeRoot)) {
            $browser = Join-Path $directory 'msedgewebview2.exe'
            if ([IO.File]::Exists($browser)) {
                $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($browser).ProductVersion
                if ($version) { [void]$versions.Add($version) }
            }
        }
    }
    $runtimeDetail = if ($versions.Count -gt 0) { '标准安装目录中发现版本 ' + (($versions | Sort-Object) -join ', ') + '；本工具没有启动浏览器。' }
        else { '标准安装目录未找到 WebView2 Evergreen Runtime。SDK DLL 不能替代运行库；请使用微软官方 x64 运行库，自行按需安装。' }
    Show-Check 'Microsoft Edge WebView2 Runtime' ($versions.Count -gt 0) $runtimeDetail

    $required = @(
        'app/CampusNetwork.ps1', 'app/CampusNetwork.Core.ps1', 'app/CampusNetwork.Diagnostics.ps1',
        'app/CampusNetwork.Service.ps1', 'app/CampusNetwork.Presentation.ps1', 'app/CampusNetwork.Retry.ps1',
        'app/CampusNetwork.Monitor.ps1',
        'app/CampusNetwork.Tray.ps1', 'app/打开校园网助手.vbs',
        'app/CampusNetwork-Lens/Start-Lens.ps1', 'app/CampusNetwork-Lens/Runtime-Lens.ps1',
        'app/CampusNetwork-Lens/CampusNetwork.Lens.exe', 'app/CampusNetwork-Lens/CampusNetwork.ProcessQuery.dll',
        'app/CampusNetwork-Lens/Microsoft.Web.WebView2.Core.dll', 'app/CampusNetwork-Lens/Microsoft.Web.WebView2.WinForms.dll',
        'app/CampusNetwork-Lens/WebView2Loader.dll', 'app/CampusNetwork-Lens/backend/Worker.ps1',
        'app/CampusNetwork-Lens/backend/Backend.ps1', 'app/CampusNetwork-Lens/backend/Probe.ps1',
        'app/CampusNetwork-Lens/web/index.html', 'app/CampusNetwork-Lens/web/app.js',
        'app/CampusNetwork-Lens/web/model.js', 'app/CampusNetwork-Lens/web/vendor/lens/index.js'
    )
    $missing = @($required | Where-Object { -not [IO.File]::Exists((Join-Path $root $_)) })
    $fileDetail = if ($missing.Count -eq 0) { '核心入口、脚本、界面与二进制均存在；完整哈希检查由 Verify-Release.ps1 执行。' }
        else { '缺少：' + ($missing -join '；') }
    Show-Check '程序基础文件' ($missing.Count -eq 0) $fileDetail
    Write-Host '程序运行时需要对 app/data、app/CampusNetwork-Lens/state 和当前用户 LocalAppData 的写入权限；此检查不创建文件来测试权限。'
    Write-Host '检查仅读取系统信息和文件元数据，不读取账号，不访问校园网，不安装依赖，不修改开机启动。'
    Write-Host '依赖存在不代表桌面启动、组织策略、运行库兼容性或校园网认证已通过验证。'
    if ($failed) { exit 1 }
    exit 0
} catch {
    Write-Host ('环境检查未完成：' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
