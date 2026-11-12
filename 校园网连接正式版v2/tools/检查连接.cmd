@echo off
setlocal
chcp 65001 >nul
echo 即将只读检查当前校园网认证状态，会访问认证服务器，但不会提交账号密码。
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0..\app\CampusNetwork.ps1" -Mode Check
set "CampusExit=%errorlevel%"
pause
exit /b %CampusExit%
