@echo off
setlocal
chcp 65001 >nul
echo 为当前 Windows 用户启用此 v2 副本的开机启动。请先保存账号，并保持发行目录位置不变。
echo 如果旧版已注册同名启动项，此操作将由 v2 接管。请只运行一个版本。
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0..\app\CampusNetwork.ps1" -Mode EnableStartup
set "CampusExit=%errorlevel%"
pause
exit /b %CampusExit%
