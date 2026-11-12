@echo off
setlocal
chcp 65001 >nul
set "CampusStrict="
if not "%~2"=="" goto usage
if "%~1"=="" goto check
if /i "%~1"=="-Strict" (
  set "CampusStrict=-Strict"
  goto check
)
goto usage
:check
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0tools\Check-Environment.ps1"
set "CampusEnvironment=%errorlevel%"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0tools\Verify-Release.ps1" %CampusStrict%
set "CampusIntegrity=%errorlevel%"
echo.
if not "%CampusEnvironment%"=="0" echo 环境检查需要处理，请查看上方说明。
if not "%CampusIntegrity%"=="0" echo 完整性检查未通过，请查看上方说明。
pause
if not "%CampusEnvironment%"=="0" exit /b 1
if not "%CampusIntegrity%"=="0" exit /b 1
exit /b 0
:usage
echo 用法：check-release.cmd [-Strict]
echo -Strict 用于未运行过的干净发行目录，禁止包含个人数据与浏览器缓存。
pause
exit /b 2
