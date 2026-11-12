@echo off
setlocal
chcp 65001 >nul
echo 停止此 v2 副本的自动监测，并记住暂停状态；不会注销当前校园网。
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0..\app\CampusNetwork.ps1" -Mode Stop
set "CampusExit=%errorlevel%"
pause
exit /b %CampusExit%
