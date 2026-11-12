@echo off
setlocal
chcp 65001 >nul
"%SystemRoot%\System32\wscript.exe" //NoLogo "%~dp0打开校园网助手.vbs"
set "CampusExit=%errorlevel%"
if not "%CampusExit%"=="0" (
  echo 启动失败，请先运行根目录的 check-release.cmd 检查程序和运行环境。
  pause
)
exit /b %CampusExit%
