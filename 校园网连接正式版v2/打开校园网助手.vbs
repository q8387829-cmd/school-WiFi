Option Explicit
Dim shell, files, root, script, mode, arguments, command, result
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
root = files.BuildPath(files.GetParentFolderName(WScript.ScriptFullName), "app")
mode = ""
If WScript.Arguments.Count > 1 Then WScript.Quit 2
If WScript.Arguments.Count = 1 Then mode = LCase(WScript.Arguments(0))
script = files.BuildPath(files.BuildPath(root, "CampusNetwork-Lens"), "Start-Lens.ps1")
arguments = ""
Select Case mode
    Case ""
    Case "/background"
        arguments = " -StartHidden"
    Case "/account"
        arguments = " -Page account"
    Case "/diagnostics"
        arguments = " -Page diagnostics"
    Case "/logs"
        arguments = " -Page logs"
    Case "/monitor"
        script = files.BuildPath(root, "CampusNetwork.ps1")
        arguments = " -Mode Run -NonInteractive"
    Case Else
        WScript.Quit 2
End Select
If Not files.FileExists(script) Then
    WScript.Echo "Campus Network Assistant: program files are missing. Please keep the complete Lens folder."
    WScript.Quit 1
End If
shell.CurrentDirectory = root
command = Chr(34) & shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe") & Chr(34) & " -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " & Chr(34) & script & Chr(34) & arguments
On Error Resume Next
result = shell.Run(command, 0, False)
If Err.Number <> 0 Then WScript.Quit 1
WScript.Quit 0
