[CmdletBinding()]
param([switch]$Fixture)
$ErrorActionPreference='Stop'
[Console]::InputEncoding=New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$OutputEncoding=[Console]::OutputEncoding
$appRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$projectRoot=[IO.Directory]::GetParent($appRoot).FullName
. (Join-Path $PSScriptRoot 'Backend.ps1')
if($Fixture){. (Join-Path $appRoot 'tests\FixtureBackend.ps1')}else{
    . (Join-Path $projectRoot 'CampusNetwork.Service.ps1')
    . (Join-Path $projectRoot 'CampusNetwork.Presentation.ps1')
}
Initialize-LensBackend -ProjectRoot $projectRoot -StateRoot (Join-Path $appRoot $(if($Fixture){'state\fixture'}else{'state\live'})) -Fixture:$Fixture
try{
    [Console]::Out.WriteLine('{"type":"ready","protocol":1}')
    while($null -ne ($line=[Console]::ReadLine())){
        $response=$null
        if($line.Length -gt 4096){$response=New-LensFailure 0 'InvalidRequest' '界面请求过长。'}else{
            try{$request=ConvertFrom-Json -InputObject $line -ErrorAction Stop;$response=Invoke-LensRequest $request}
            catch{$response=New-LensFailure 0 'InvalidRequest' '无法读取界面请求。'}
        }
        [Console]::Out.WriteLine(($response|ConvertTo-Json -Depth 9 -Compress))
        [Console]::Out.Flush()
    }
}finally{Close-LensBackend}
