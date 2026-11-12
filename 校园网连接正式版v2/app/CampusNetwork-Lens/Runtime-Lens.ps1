# Runtime files live in the normal per-user application directory. The original
# application root continues to own web assets, backend scripts and configuration.
function Get-LensRuntimeFileHash([string]$Path) {
    $algorithm=[Security.Cryptography.SHA256]::Create()
    $stream=$null
    try{
        $stream=[IO.File]::OpenRead($Path)
        return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-','')
    }finally{if($null -ne $stream){$stream.Dispose()};$algorithm.Dispose()}
}
function Publish-LensRuntime {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$AppRoot,[string]$Executable='CampusNetwork.Lens.exe')
    $applicationRoot=[IO.Path]::GetFullPath($AppRoot)
    if([IO.Path]::GetFileName($Executable) -ne $Executable -or [IO.Path]::GetExtension($Executable) -ne '.exe'){throw 'Invalid runtime executable name'}
    $names=@($Executable,'Microsoft.Web.WebView2.Core.dll','Microsoft.Web.WebView2.WinForms.dll','WebView2Loader.dll')
    $records=@(foreach($name in $names){
        $path=Join-Path $applicationRoot $name
        if(-not [IO.File]::Exists($path)){throw ('Missing runtime file: '+$name)}
        [pscustomobject]@{Name=$name;Path=$path;Hash=(Get-LensRuntimeFileHash $path)}
    })
    $identity=$applicationRoot.TrimEnd('\','/').ToLowerInvariant()+'|'+(($records|ForEach-Object{$_.Name+':'+$_.Hash}) -join '|')
    $hash=[Security.Cryptography.SHA256]::Create()
    try{$version=([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity)))).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}
    $base=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CampusNetworkLens/runtime'
    $destination=Join-Path $base $version
    if(-not [IO.Directory]::Exists($destination)){
        [void][IO.Directory]::CreateDirectory($base)
        $staging=Join-Path $base ('.staging-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($staging)
        foreach($record in $records){
            # Write new files, so workspace security labels are never copied.
            $target=Join-Path $staging $record.Name
            [IO.File]::WriteAllBytes($target,[IO.File]::ReadAllBytes($record.Path))
            if((Get-LensRuntimeFileHash $target) -ne $record.Hash){throw 'Runtime publication verification failed'}
        }
        try{[IO.Directory]::Move($staging,$destination)}catch{if(-not [IO.Directory]::Exists($destination)){throw}}
    }
    foreach($record in $records){
        $target=Join-Path $destination $record.Name
        if(-not [IO.File]::Exists($target) -or (Get-LensRuntimeFileHash $target) -ne $record.Hash){throw 'Published runtime files do not match the application'}
    }
    return (Join-Path $destination $Executable)
}
