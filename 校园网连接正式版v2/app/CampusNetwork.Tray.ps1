[CmdletBinding()]
param([switch]$StartHidden,[ValidateSet('Status','Account','Diagnostics','Logs')][string]$PreviewPage='Status',[string]$PreviewPath)
$ErrorActionPreference='Stop'
# Compatibility entry for existing PowerShell startup shortcuts. The Lens host
# provides the only daily window and tray. Historical drawing sources are unused.
$page=@{Status='overview';Account='account';Diagnostics='diagnostics';Logs='logs'}[$PreviewPage]
& (Join-Path $PSScriptRoot 'CampusNetwork-Lens\Start-Lens.ps1') -StartHidden:$StartHidden -Page $page
