@echo off
setlocal
chcp 65001 >nul
echo 即将检查当前网络与认证端口，会发起网络检查，但不会提交账号密码。
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0..\app\CampusNetwork.ps1" -Mode Diagnose
set "CampusExit=%errorlevel%"
pause
exit /b %CampusExit%
