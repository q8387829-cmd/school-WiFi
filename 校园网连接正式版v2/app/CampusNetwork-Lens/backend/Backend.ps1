Set-StrictMode -Version 2.0

function Get-LensField($Value,[string]$Name,$Default=$null) {
    if($null -eq $Value){return $Default}
    if($Value -is [Collections.IDictionary]){if($Value.Contains($Name)){return $Value[$Name]};return $Default}
    if($null -ne $Value.PSObject.Properties[$Name]){return $Value.$Name};return $Default
}

function Protect-LensText($Value,[int]$Limit=16000) {
    $text=[string]$Value
    $safe=foreach($line in @($text -split '\r\n|\n|\r')){
        $inspection=$line
        for($round=0;$round -lt 2;$round++){
            try{$inspection=[uri]::UnescapeDataString($inspection)}catch{}
            $inspection=[regex]::Replace($inspection,'\\u00([a-fA-F0-9]{2})',{param($m) [string][char][Convert]::ToInt32($m.Groups[1].Value,16)})
        }
        if($inspection -match '(?i)(?:user[_\s-]*password|password|passwd|pwd|access[_-]?token|refresh[_-]?token|authorization|token|密码|口令)["\x27]?\s*[:=：]\s*\S+' -or $inspection -match '(?i)https?://\S*/(?:eportal/)?portal/login'){
            '[已隐藏包含认证信息的记录]'
        }else{$line}
    }
    $result=($safe -join [Environment]::NewLine)
    if($result.Length -gt $Limit){$result=$result.Substring(0,$Limit)}
    return $result
}

function Initialize-LensBackend([string]$ProjectRoot,[string]$StateRoot,[switch]$Fixture) {
    $script:Lens=@{ProjectRoot=[IO.Path]::GetFullPath($ProjectRoot);StateRoot=[IO.Path]::GetFullPath($StateRoot);Fixture=[bool]$Fixture;Cache=@{};Probe=$null;LastProbe=$null;Diagnostic=$null}
}

function ConvertTo-LensTime($Value) {
    if($Value -is [datetimeoffset]){return $Value.ToUniversalTime()}
    if($Value -is [datetime]){return [datetimeoffset]$Value.ToUniversalTime()}
    $parsed=[datetimeoffset]::MinValue
    if([datetimeoffset]::TryParse([string]$Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal,[ref]$parsed)){return $parsed.ToUniversalTime()}
    return $null
}

function Test-LensProbePath([string]$Path) {
    $expected=[IO.Path]::GetFullPath((Join-Path $script:Lens.StateRoot 'diagnostics')).TrimEnd('\')+'\'
    $full=[IO.Path]::GetFullPath($Path)
    return $full.StartsWith($expected,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($full) -match '^probe-[a-f0-9]{32}\.json$'
}

function Remove-LensProbeFile([string]$Path) {
    if(-not(Test-LensProbePath $Path)){throw 'Invalid owned diagnostic path'}
    foreach($file in @($Path,($Path+'.tmp'))){if([IO.File]::Exists($file)){[IO.File]::Delete($file)}}
}

function Stop-LensProbe {
    $task=$script:Lens.Probe
    $script:Lens.Probe=$null
    if($null -eq $task){return}
    try{if(-not $task.Process.HasExited){$task.Process.Kill();[void]$task.Process.WaitForExit(2000)}}finally{
        $task.Process.Dispose();Remove-LensProbeFile $task.ResultPath
    }
}

function New-LensProbe {
    if($null -ne $script:Lens.Probe){return}
    $directory=Join-Path $script:Lens.StateRoot 'diagnostics'
    [void][IO.Directory]::CreateDirectory($directory)
    $result=Join-Path $directory ('probe-'+[guid]::NewGuid().ToString('N')+'.json')
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $info.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'Probe.ps1')+'" -ResultPath "'+$result+'"'+$(if($script:Lens.Fixture){' -Fixture'}else{''})
    $info.WorkingDirectory=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $process=[Diagnostics.Process]::Start($info)
    $process.BeginOutputReadLine();$process.BeginErrorReadLine()
    $script:Lens.Probe=[pscustomobject]@{Process=$process;ResultPath=$result;Timer=[Diagnostics.Stopwatch]::StartNew();StartedAt=$process.StartTime.ToUniversalTime().Ticks.ToString()}
    $script:Lens.Diagnostic=$null
}

function Update-LensProbe {
    $task=$script:Lens.Probe
    if($null -eq $task){return}
    if(-not $task.Process.HasExited -and $task.Timer.ElapsedMilliseconds -lt 55000){return}
    $timedOut=-not $task.Process.HasExited
    $result=$null
    try{
        if($timedOut){$task.Process.Kill();[void]$task.Process.WaitForExit(2000)}
        if(-not $timedOut -and [IO.File]::Exists($task.ResultPath)){$result=[IO.File]::ReadAllText($task.ResultPath)|ConvertFrom-Json -ErrorAction Stop}
    }catch{}finally{$script:Lens.Probe=$null;$task.Process.Dispose();Remove-LensProbeFile $task.ResultPath}
    if($null -eq $result){
        $result=[pscustomobject]@{AuthState='Unknown';ReasonCode='DiagnosticIncomplete';Success=$false;Text=$(if($timedOut){'诊断超过等待时间，未能确认认证状态。'}else{'诊断未能完成，尚不能确认认证状态。'});Suggestion='检查校园网连接后重试。';VpnActive=$false;CompletedAt=[datetime]::UtcNow.ToString('o')}
    }
    $auth=[string](Get-LensField $result 'AuthState' 'Unknown')
    if($auth -notin @('Online','Offline','Unknown')){$auth='Unknown'}
    $completed=ConvertTo-LensTime (Get-LensField $result 'CompletedAt' '')
    if($null -eq $completed){$completed=[datetimeoffset]::UtcNow}
    $safeResult=[pscustomobject]@{AuthState=$auth;ReasonCode=(Protect-LensText (Get-LensField $result 'ReasonCode' '') 80);Success=($auth -ne 'Unknown');Text=(Protect-LensText (Get-LensField $result 'Text' '') 16000);Suggestion=(Protect-LensText (Get-LensField $result 'Suggestion' '') 1000);VpnActive=[bool](Get-LensField $result 'VpnActive' $false);CompletedAt=$completed.ToString('o')}
    $presentation=ConvertTo-CampusDiagnosticPresentation -Text $safeResult.Text -Success $safeResult.Success
    $safeResult|Add-Member NoteProperty Presentation ([pscustomobject]@{Title=(Protect-LensText $presentation.Title 100);Summary=(Protect-LensText $presentation.Summary 1500);Tone=[string]$presentation.Tone;Advice=(Protect-LensText $presentation.Advice 1500);Items=@($presentation.Items|ForEach-Object{[pscustomobject]@{Label=(Protect-LensText $_.Label 100);Value=(Protect-LensText $_.Value 200);Tone=[string]$_.Tone}})})
    $script:Lens.LastProbe=$safeResult;$script:Lens.Diagnostic=$safeResult
}

function Get-LensState {
    Update-LensProbe
    $raw=Get-CampusAppViewModel -ProjectRoot $script:Lens.ProjectRoot -Cache $script:Lens.Cache
    $model=[ordered]@{}
    foreach($key in @('MonitorRunning','VpnActive','StartupEnabled','CredentialAvailable','MonitorOnLaunch')){$model[$key]=[bool](Get-LensField $raw $key $false)}
    foreach($key in @('AuthState','MonitorState','StatusText','DetailText','Suggestion','UpdatedAt','LastLoginAt','LastError','Account','Carrier','NextAttemptUtc','RecoveryUntilUtc')){$model[$key]=Protect-LensText (Get-LensField $raw $key '') 1500}
    if($model.AuthState -notin @('Online','Offline','Unknown')){$model.AuthState='Unknown'}
    $model.ReadOnlySettings=$false;$model.Source='none';$model.ObservedAt='';$model.ExpiresAt=''
    $now=[datetimeoffset]::UtcNow
    if($model.MonitorRunning){
        $observed=ConvertTo-LensTime $model.UpdatedAt
        if($null -ne $observed -and $observed -le $now.AddSeconds(5) -and $observed.AddSeconds(45) -gt $now -and $model.AuthState -ne 'Unknown'){
            $model.Source='monitor';$model.ObservedAt=$observed.ToString('o');$model.ExpiresAt=$observed.AddSeconds(45).ToString('o')
        }elseif($model.AuthState -ne 'Unknown'){
            $model.AuthState='Unknown';$model.StatusText='等待最新监测结果';$model.DetailText='监测记录已过期或时间无效，尚未确认当前认证状态。'
        }
    }else{
        $model.AuthState='Unknown'
        if($null -ne $script:Lens.LastProbe){
            $observed=ConvertTo-LensTime $script:Lens.LastProbe.CompletedAt
            if($null -ne $observed -and $observed -le $now.AddSeconds(5) -and $observed.AddSeconds(30) -gt $now){
                $model.AuthState=$script:Lens.LastProbe.AuthState;$model.Source='probe';$model.ObservedAt=$observed.ToString('o');$model.ExpiresAt=$observed.AddSeconds(30).ToString('o');$model.UpdatedAt=$observed.ToString('o');$model.DetailText=Protect-LensText $script:Lens.LastProbe.Text 1500;$model.Suggestion=Protect-LensText $script:Lens.LastProbe.Suggestion 1500;$model.VpnActive=$script:Lens.LastProbe.VpnActive
                $model.StatusText=switch($model.AuthState){'Online'{'校园网已连接'}'Offline'{'校园网尚未登录'}default{'尚未确认认证状态'}}
            }
        }
    }
    return [pscustomobject]@{Model=[pscustomobject]$model;Diagnostic=[pscustomobject]@{Running=($null -ne $script:Lens.Probe);Result=$script:Lens.Diagnostic}}
}

function Get-LensOwnedProbe {
    $variable=Get-Variable Lens -Scope Script -ErrorAction SilentlyContinue
    if($null -ne $variable -and $null -ne $script:Lens.Probe){return [pscustomobject]@{id=$script:Lens.Probe.Process.Id;startedAt=$script:Lens.Probe.StartedAt}}
    return $null
}
function New-LensFailure([int]$Id,[string]$Code,[string]$Message) { return [pscustomobject]@{id=$Id;ok=$false;error=[pscustomobject]@{code=$Code;message=$Message};data=$null;ownedProbe=(Get-LensOwnedProbe)} }

function Test-LensPayload([string]$Command,$Payload,[bool]$Present) {
    if($Command -notin @('SaveCredential','SetStartup','SetLaunchPreference','ForgetCredential')){return -not $Present}
    if(-not $Present -or $null -eq $Payload -or ($Payload -isnot [pscustomobject] -and $Payload -isnot [Collections.IDictionary])){return $false}
    $names=@($Payload.PSObject.Properties.Name);if($Payload -is [Collections.IDictionary]){$names=@($Payload.Keys)}
    if($Command -eq 'SaveCredential'){
        $account=Get-LensField $Payload 'account';$carrier=Get-LensField $Payload 'carrier';$password=Get-LensField $Payload 'password'
        return $names.Count -eq 3 -and $account -is [string] -and $account.Length -le 128 -and -not [string]::IsNullOrWhiteSpace($account) -and $carrier -cin @('campus','unicom','cmcc','telecom') -and $password -is [string] -and $password.Length -le 256
    }
    if($Command -eq 'ForgetCredential'){$confirmed=Get-LensField $Payload 'confirmed';return $names.Count -eq 1 -and $confirmed -is [bool] -and $confirmed}
    return $names.Count -eq 1 -and (Get-LensField $Payload 'enabled') -is [bool]
}

function Wait-LensMonitorStopped {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(Test-CampusMonitorRunning -ProjectRoot $script:Lens.ProjectRoot){
        # A monitor may be finishing one HTTP request with a 10-second timeout.
        # Stay within the desktop bridge's 20-second request deadline.
        if($watch.ElapsedMilliseconds -ge 15000){throw 'Monitor stop timeout'}
        Start-Sleep -Milliseconds 100
    }
}

function Invoke-LensRequest($Request) {
    if($null -eq $Request -or ($Request -isnot [pscustomobject] -and $Request -isnot [Collections.IDictionary])){return New-LensFailure 0 'InvalidRequest' '无效的界面请求。'}
    $id=Get-LensField $Request 'id' 0
    $command=Get-LensField $Request 'command' ''
    $names=@($Request.PSObject.Properties.Name)
    if($Request -is [Collections.IDictionary]){$names=@($Request.Keys)}
    if($id -isnot [int] -and $id -isnot [long]){return New-LensFailure 0 'InvalidRequest' '无效的界面请求。'}
    $hasPayload=$names -ccontains 'payload';$payload=Get-LensField $Request 'payload'
    if($id -le 0 -or $id -gt 2147483647 -or $command -isnot [string] -or $names.Count -ne $(if($hasPayload){3}else{2}) -or @($names|Where-Object{$_ -cnotin @('id','command','payload')}).Count -gt 0){return New-LensFailure 0 'InvalidRequest' '无效的界面请求。'}
    if($command -cnotin @('GetState','CheckNow','StartMonitor','StopMonitor','StartDiagnostics','CancelDiagnostics','GetLogs','SaveCredential','SetStartup','SetLaunchPreference','ForgetCredential')){return New-LensFailure $id 'UnsupportedCommand' '此界面不提供该操作。'}
    if(-not(Test-LensPayload $command $payload $hasPayload)){return New-LensFailure $id 'InvalidRequest' '请检查操作参数，确认后重试。'}
    try{
        $feedback=''
        switch($command){
            'StartMonitor'{
                $before=Get-CampusAppViewModel -ProjectRoot $script:Lens.ProjectRoot -Cache $script:Lens.Cache
                if(-not $before.MonitorRunning){
                    if(-not $before.CredentialAvailable){return New-LensFailure $id 'MissingCredential' '请先在账号与设置中保存校园网账号。'}
                    [void](Start-CampusMonitor -ProjectRoot $script:Lens.ProjectRoot);$script:Lens.LastProbe=$null
                }
                $feedback='已请求开启自动监测，实际状态将自动更新。'
            }
            'StopMonitor'{
                $before=Get-CampusAppViewModel -ProjectRoot $script:Lens.ProjectRoot -Cache $script:Lens.Cache
                if($before.MonitorRunning){[void](Stop-CampusMonitor -ProjectRoot $script:Lens.ProjectRoot)}
                $script:Lens.LastProbe=$null;$feedback='已请求暂停自动监测，正在等待后台确认。'
            }
            'CheckNow'{
                $before=Get-CampusAppViewModel -ProjectRoot $script:Lens.ProjectRoot -Cache $script:Lens.Cache
                if($before.MonitorRunning){[void](Request-CampusMonitorCheck -ProjectRoot $script:Lens.ProjectRoot)}
                else{New-LensProbe}
                $feedback=''
            }
            'StartDiagnostics'{New-LensProbe;$feedback='网络诊断已开始，结果来自真实检查。'}
            'CancelDiagnostics'{Stop-LensProbe;$feedback='已结束本窗口的检查任务。'}
            'SaveCredential'{
                $secret=New-Object Security.SecureString
                try{
                    foreach($character in $payload.password.ToCharArray()){$secret.AppendChar($character)}
                    $secret.MakeReadOnly()
                    Save-CampusUiCredential -ProjectRoot $script:Lens.ProjectRoot -Account $payload.account -Carrier $payload.carrier -Password $secret
                }finally{$secret.Dispose();$payload.password=''}
                $script:Lens.Cache=@{}
                $feedback='账号已在本机加密保存，后续重连会读取最新配置。'
            }
            'SetStartup'{Set-CampusStartup -ProjectRoot $script:Lens.ProjectRoot -Enabled $payload.enabled;$script:Lens.Cache=@{};$feedback='开机启动设置已更新。'}
            'SetLaunchPreference'{Set-CampusUiPreferences -ProjectRoot $script:Lens.ProjectRoot -MonitorOnLaunch $payload.enabled;$feedback='启动时监测设置已更新。'}
            'ForgetCredential'{
                Stop-CampusMonitor -ProjectRoot $script:Lens.ProjectRoot
                Wait-LensMonitorStopped
                Clear-CampusUiCredential -ProjectRoot $script:Lens.ProjectRoot
                $script:Lens.Cache=@{};$script:Lens.LastProbe=$null
                $feedback='本机账号已清除，监测已停止。'
            }
            'GetLogs'{
                $data=[pscustomobject]@{Text=(Protect-LensText (Get-CampusRecentLog -ProjectRoot $script:Lens.ProjectRoot -Lines 100) 24000)}
            }
        }
        if($command -ne 'GetLogs'){$data=Get-LensState;$data|Add-Member NoteProperty Feedback $feedback}
        $owned=Get-LensOwnedProbe
        return [pscustomobject]@{id=[int]$id;ok=$true;data=$data;error=$null;ownedProbe=$owned}
    }catch{
        $failureMessage=$_.Exception.Message
        $safeMessage=switch($command){
            'SaveCredential'{'保存失败：请检查账号和线路。首次保存或更换账号、运营商时必须填写密码。'}
            'SetStartup'{
                $startupMessage=$failureMessage
                if($startupMessage -in @(
                    '无法读取现有开机启动项，请检查启动文件夹的访问权限后重试。',
                    '同名启动项不是本工具创建的，已保留原项。请在 Windows 启动文件夹中检查 CampusNetworkReconnect.lnk。',
                    '开机启动更新失败，原快捷方式已保存在当前目录的 data/startup-backups，请检查启动文件夹权限后重试。'
                )){$startupMessage}
                else{'无法更新开机启动。请先保存账号，确认程序文件完整，并检查启动文件夹的访问权限。'}
            }
            'ForgetCredential'{'尚未清除账号：请确认监测已停止后重试。'}
            default{'操作未完成，请检查账号状态、校园网连接，或稍后重试。'}
        }
        return New-LensFailure $id 'OperationFailed' $safeMessage
    }
}

function Close-LensBackend { if($null -ne (Get-Variable Lens -Scope Script -ErrorAction SilentlyContinue)){Stop-LensProbe} }
