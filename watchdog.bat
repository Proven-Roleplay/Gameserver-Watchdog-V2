@echo off
set "BASE_DIR=%~dp0"
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%BASE_DIR%GameServerWatchdog.ps1" -ConfigPath "%BASE_DIR%config.json"
exit /b
