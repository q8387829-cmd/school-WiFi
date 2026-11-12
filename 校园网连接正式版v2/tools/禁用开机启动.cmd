@echo off
setlocal
chcp 65001 >nul
echo 仅移除此 v2 副本拥有的开机启动项；其他位置或版本的启动项不会被删除。
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0..\app\CampusNetwork.ps1" -Mode DisableStartup
set "CampusExit=%errorlevel%"
pause
exit /b %CampusExit%
