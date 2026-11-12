[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ResultPath,[switch]$Fixture)
$ErrorActionPreference='Stop'
$appRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stateRoot=Join-Path $appRoot $(if($Fixture){'state\fixture'}else{'state\live'})
$allowed=[IO.Path]::GetFullPath((Join-Path $stateRoot 'diagnostics')).TrimEnd('\')+'\'
$target=[IO.Path]::GetFullPath($ResultPath)
if(-not $target.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($target) -notmatch '^probe-[a-f0-9]{32}\.json$'){throw 'Invalid diagnostic destination'}
$client=$null
try{
    if($Fixture){. (Join-Path $appRoot 'tests\FixtureBackend.ps1')}else{. (Join-Path ([IO.Directory]::GetParent($appRoot).FullName) 'CampusNetwork.Service.ps1')}
    $client=New-CampusHttpClient
    $snapshot=Get-CampusSnapshot $client
    $result=[ordered]@{Success=$snapshot.State -ne 'Unknown';AuthState=$snapshot.State;ReasonCode=$snapshot.ReasonCode;Text=(Get-CampusDiagnosticText $snapshot);Suggestion=$snapshot.Suggestion;VpnActive=$snapshot.VpnActive;CompletedAt=[datetime]::UtcNow.ToString('o')}
}catch{
    if($Fixture){[Console]::Error.WriteLine('Fixture probe failure: '+$_.Exception.Message)}
    $result=[ordered]@{Success=$false;AuthState='Unknown';ReasonCode='DiagnosticIncomplete';Text='诊断未能完成，尚不能确认认证状态。';Suggestion='确认校园网连接后再试。';VpnActive=$false;CompletedAt=[datetime]::UtcNow.ToString('o')}
}finally{if($null -ne $client){$client.Dispose()}}
try{
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
    [IO.File]::WriteAllText($target+'.tmp',($result|ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))
    [IO.File]::Move($target+'.tmp',$target)
}finally{if([IO.File]::Exists($target+'.tmp')){[IO.File]::Delete($target+'.tmp')}}
