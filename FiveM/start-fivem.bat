@echo off
title FiveM Server
setlocal

set "SERVER_DIR=C:\GameServers\FiveM"

cd /d "%SERVER_DIR%"

echo [%date% %time%] Starting FiveM...
FXServer.exe +exec server.cfg
echo [%date% %time%] FiveM exited.

endlocal
