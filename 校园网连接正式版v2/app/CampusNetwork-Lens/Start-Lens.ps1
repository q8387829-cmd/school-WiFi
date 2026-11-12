[CmdletBinding()]
param([switch]$StartHidden,[ValidateSet('overview','account','diagnostics','logs','materials','original')][string]$Page='overview',[switch]$PreserveMonitor)
$ErrorActionPreference='Stop'
if($Page -in @('materials','original')){$Page='overview'}
. (Join-Path $PSScriptRoot 'Runtime-Lens.ps1')
$info=New-Object Diagnostics.ProcessStartInfo
$info.FileName=Publish-LensRuntime -AppRoot $PSScriptRoot
$info.WorkingDirectory=$PSScriptRoot
$info.Arguments='--app-root="'+$PSScriptRoot+'" --page='+$Page+$(if($StartHidden){' --background'}else{''})+$(if($PreserveMonitor){' --preserve-monitor'}else{''})
$info.UseShellExecute=$false
$info.CreateNoWindow=$true
$info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Normal
[void][Diagnostics.Process]::Start($info)
