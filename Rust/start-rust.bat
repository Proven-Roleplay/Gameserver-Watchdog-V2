@echo off
title Rust Server
setlocal

set "SERVER_DIR=C:\GameServers\Rust"

set "RUST_PORT=28015"
set "RUST_RCON_PORT=28016"
set "RUST_RCON_PASSWORD=ChangeThisToAStrongPassword"
set "RUST_HOSTNAME=My Rust Server"
set "RUST_IDENTITY=main"
set "RUST_LEVEL=Procedural Map"
set "RUST_SEED=12345"
set "RUST_WORLDSIZE=4000"
set "RUST_MAXPLAYERS=50"
set "RUST_DESCRIPTION=Hosted on Windows"

cd /d "%SERVER_DIR%"

echo [%date% %time%] Starting Rust...
RustDedicated.exe -batchmode -nographics ^
 +server.port %RUST_PORT% ^
 +server.level "%RUST_LEVEL%" ^
 +server.seed %RUST_SEED% ^
 +server.worldsize %RUST_WORLDSIZE% ^
 +server.maxplayers %RUST_MAXPLAYERS% ^
 +server.hostname "%RUST_HOSTNAME%" ^
 +server.description "%RUST_DESCRIPTION%" ^
 +server.identity "%RUST_IDENTITY%" ^
 +rcon.port %RUST_RCON_PORT% ^
 +rcon.password "%RUST_RCON_PASSWORD%" ^
 +rcon.web 1

echo [%date% %time%] Rust exited.

endlocal
