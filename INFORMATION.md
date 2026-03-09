# Game Server Watchdog v2

### Automated FiveM & Rust Server Monitoring System

**Created by Majestic44**

---

# Overview

Game Server Watchdog v2 is a monitoring and automation system designed for Windows-hosted game servers. It continuously monitors server processes and ensures that services remain operational.

This system is designed specifically for environments running **FiveM** and **Rust Dedicated Servers**, but it can be easily extended to monitor additional services.

The watchdog performs several automated functions:

• Detects server crashes or unexpected shutdowns
• Automatically restarts failed servers
• Limits restart loops to prevent crash storms
• Sends Discord webhook alerts for server events
• Logs CPU and memory usage metrics
• Performs automated Rust updates via SteamCMD
• Rotates logs daily for long-term monitoring
• Provides centralized configuration through a JSON file

This system is intended for **Windows dedicated servers running game infrastructure**.

---

# Features

## Crash Detection

The watchdog monitors running processes for each configured server.

If a process stops unexpectedly, the watchdog will:

1. Log the shutdown event
2. Send a Discord alert
3. Restart the server automatically

---

## Restart Protection

Servers that crash repeatedly may indicate configuration errors or mod/plugin issues.

To prevent infinite restart loops, the watchdog enforces limits:

Example policy:

* Maximum restarts within 15 minutes: **5**
* Cooldown period after limit reached: **15 minutes**

If the limit is reached:

• Restarts will pause temporarily
• A Discord alert will be sent
• Logging will record the cooldown event

---

## Discord Webhook Alerts

The system can notify a Discord channel whenever important events occur.

Events include:

• Server started
• Server crash detected
• Restart attempts
• Restart limits reached
• Rust update started
• Rust update completed

Discord notifications allow administrators to monitor server health remotely.

---

## Resource Monitoring

The watchdog collects resource usage statistics for each server.

Metrics recorded:

• CPU usage
• Memory usage (Working Set)
• Private memory allocation
• Thread count
• Handle count

Metrics are written to:

```
C:\GameServers\logs\metrics.log
```

Example entry:

```
[2026-03-09 14:11:30] FiveM PID=1234 CPU=8% WS=512MB Private=478MB Threads=71 Handles=1432
```

This allows long-term server performance monitoring.

---

## Rust Auto Update via SteamCMD

Rust servers frequently receive updates.

This watchdog can automatically update Rust using SteamCMD.

The update command executed:

```
steamcmd +force_install_dir C:\GameServers\Rust +login anonymous +app_update 258550 validate +quit
```

Updates occur:

• At startup
• Periodically (configurable interval)
• Only when the server is offline

---

# Folder Structure

Recommended structure:

```
C:\GameServers\
│
├── watchdog.bat
├── GameServerWatchdog.ps1
├── config.json
│
├── logs\
│   ├── watchdog.log
│   └── metrics.log
│
├── FiveM\
│   ├── FXServer.exe
│   └── start-fivem.bat
│
├── Rust\
│   ├── RustDedicated.exe
│   └── start-rust.bat
│
└── SteamCMD\
    └── steamcmd.exe
```

---

# File Descriptions

## watchdog.bat

A lightweight bootstrap script that launches the PowerShell watchdog.

This script is what Windows Task Scheduler executes during system startup.

---

## GameServerWatchdog.ps1

The main monitoring engine.

Responsibilities include:

• Monitoring server processes
• Restarting crashed servers
• Sending Discord alerts
• Logging server performance
• Performing Rust updates
• Enforcing restart limits

---

## config.json

Central configuration file used by the watchdog.

Administrators should modify this file instead of editing the script.

Configuration includes:

• Discord webhook
• Server paths
• Update intervals
• Restart limits
• Monitoring intervals

---

## start-fivem.bat

Launch script for the FiveM server.

Example command:

```
FXServer.exe +exec server.cfg
```

---

## start-rust.bat

Launch script for the Rust server.

Example parameters include:

• server hostname
• world seed
• world size
• max players
• RCON settings

---

# Installation Guide

## Step 1 — Extract Files

Extract the watchdog package to:

```
C:\GameServers
```

---

## Step 2 — Install SteamCMD

Download SteamCMD:

https://developer.valvesoftware.com/wiki/SteamCMD

Place it in:

```
C:\GameServers\SteamCMD\
```

Confirm the file exists:

```
C:\GameServers\SteamCMD\steamcmd.exe
```

---

## Step 3 — Configure Servers

Open:

```
config.json
```

Update the following fields:

```
DiscordWebhookUrl
FiveMDirectory
RustDirectory
SteamCMDPath
```

---

## Step 4 — Configure Discord Alerts

1. Open Discord
2. Go to the server channel
3. Click **Edit Channel**
4. Select **Integrations**
5. Create a **Webhook**
6. Copy the webhook URL

Insert the webhook URL into:

```
config.json
```

---

## Step 5 — Configure Rust Server

Edit:

```
Rust\start-rust.bat
```

Change:

• Server name
• RCON password
• world size
• seed
• player limits

---

## Step 6 — Configure FiveM Server

Edit:

```
FiveM\start-fivem.bat
```

Ensure the correct path to:

```
FXServer.exe
```

---

# Task Scheduler Setup

The watchdog must run automatically when Windows starts.

### Open Task Scheduler

Create a new task.

### General

Name:

```
Game Server Watchdog
```

Enable:

```
Run whether user is logged on or not
Run with highest privileges
```

---

### Trigger

```
At system startup
```

---

### Action

Program:

```
C:\GameServers\watchdog.bat
```

---

### Settings

Recommended options:

• Allow task to run on demand
• Restart task on failure
• Do not stop task if running longer than expected

---

# Logs

Logs are located in:

```
C:\GameServers\logs
```

Files include:

### watchdog.log

Operational events such as:

• server starts
• crashes
• restarts
• update checks

---

### metrics.log

Performance statistics including:

• CPU usage
• memory usage
• process metrics

---

# Troubleshooting

## Server not restarting

Check:

```
watchdog.log
```

Common causes:

• incorrect server paths
• incorrect process names
• missing start scripts

---

## Discord alerts not working

Confirm:

```
DiscordWebhookUrl
```

is correct in `config.json`.

---

## Rust not updating

Confirm SteamCMD exists:

```
C:\GameServers\SteamCMD\steamcmd.exe
```

---

# Security Recommendations

• Use strong RCON passwords
• Restrict RCON ports via firewall
• Run servers under a dedicated Windows user
• Limit write permissions on configuration files

---

# Future Enhancements

Potential improvements:

• txAdmin health monitoring for FiveM
• automatic FiveM artifact updates
• web dashboard for server metrics
• Grafana/Prometheus integration
• automatic server backups

---

# Credits

Game Server Watchdog v2
**Created by Majestic44**

Designed for Windows-based dedicated game servers hosting FiveM and Rust.

---
