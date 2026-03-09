param(
    [string]$ConfigPath = ".\config.json"
)

$ErrorActionPreference = "Stop"

function Resolve-AbsolutePath {
    param([string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $PathValue))
}

$ConfigPath = Resolve-AbsolutePath -PathValue $ConfigPath
if (!(Test-Path $ConfigPath)) {
    Write-Host "Config file not found: $ConfigPath"
    exit 1
}

$config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
$BaseDir = $config.BaseDir
$LogDir  = Join-Path $BaseDir "logs"

if (!(Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$MainLog     = Join-Path $LogDir "watchdog.log"
$MetricLog   = Join-Path $LogDir "metrics.log"
$StateFile   = Join-Path $LogDir "state.json"
$LastDailyRotation = $null

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -Path $MainLog -Value $line
    Write-Host $line
}

function Invoke-DiscordWebhook {
    param(
        [string]$Title,
        [string]$Description,
        [int]$Color = 3447003
    )

    if (-not $config.Discord.Enabled) { return }
    if ([string]::IsNullOrWhiteSpace($config.Discord.WebhookUrl) -or $config.Discord.WebhookUrl -eq "PASTE_DISCORD_WEBHOOK_URL_HERE") { return }

    try {
        $payload = @{
            username = $config.Discord.Username
            embeds   = @(
                @{
                    title       = $Title
                    description = $Description
                    color       = $Color
                    timestamp   = (Get-Date).ToUniversalTime().ToString("o")
                }
            )
        } | ConvertTo-Json -Depth 6

        Invoke-RestMethod -Uri $config.Discord.WebhookUrl -Method Post -ContentType "application/json" -Body $payload | Out-Null
    }
    catch {
        Write-Log "Discord webhook failed: $($_.Exception.Message)" "ERROR"
    }
}

function Get-ServerDefinitions {
    $servers = @()
    foreach ($name in @("FiveM", "Rust")) {
        $s = $config.$name
        if ($null -ne $s -and $s.Enabled) {
            $servers += @{
                Name             = $s.Name
                ProcessName      = $s.ProcessName
                StartScript      = $s.StartScript
                WorkingDirectory = $s.WorkingDirectory
                StartGraceSeconds= [int]$s.StartGraceSeconds
                IsRust           = ($name -eq "Rust")
            }
        }
    }
    return $servers
}

$Servers = Get-ServerDefinitions

$ServerState = @{}
foreach ($server in $Servers) {
    $ServerState[$server.Name] = @{
        RestartTimes        = New-Object System.Collections.Generic.List[datetime]
        CooldownUntil       = $null
        LastKnownRunningPid = $null
        LastExitDetectedAt  = $null
        LastUpdateCheck     = $null
        RestartCount        = 0
    }
}

function Save-State {
    $export = @{}
    foreach ($key in $ServerState.Keys) {
        $s = $ServerState[$key]
        $export[$key] = @{
            RestartTimes        = @($s.RestartTimes | ForEach-Object { $_.ToString("o") })
            CooldownUntil       = if ($s.CooldownUntil) { $s.CooldownUntil.ToString("o") } else { $null }
            LastKnownRunningPid = $s.LastKnownRunningPid
            LastExitDetectedAt  = if ($s.LastExitDetectedAt) { $s.LastExitDetectedAt.ToString("o") } else { $null }
            LastUpdateCheck     = if ($s.LastUpdateCheck) { $s.LastUpdateCheck.ToString("o") } else { $null }
            RestartCount        = $s.RestartCount
        }
    }
    ($export | ConvertTo-Json -Depth 8) | Set-Content -Path $StateFile
}

function Load-State {
    if (!(Test-Path $StateFile)) { return }
    try {
        $data = Get-Content -Raw -Path $StateFile | ConvertFrom-Json
        foreach ($serverName in $data.PSObject.Properties.Name) {
            if (-not $ServerState.ContainsKey($serverName)) { continue }
            $raw = $data.$serverName
            $state = $ServerState[$serverName]
            $state.RestartTimes.Clear()
            foreach ($dt in @($raw.RestartTimes)) {
                if ($dt) { $state.RestartTimes.Add([datetime]$dt) }
            }
            if ($raw.CooldownUntil) { $state.CooldownUntil = [datetime]$raw.CooldownUntil }
            if ($raw.LastKnownRunningPid) { $state.LastKnownRunningPid = [int]$raw.LastKnownRunningPid }
            if ($raw.LastExitDetectedAt) { $state.LastExitDetectedAt = [datetime]$raw.LastExitDetectedAt }
            if ($raw.LastUpdateCheck) { $state.LastUpdateCheck = [datetime]$raw.LastUpdateCheck }
            if ($raw.RestartCount) { $state.RestartCount = [int]$raw.RestartCount }
        }
    }
    catch {
        Write-Log "State file load failed: $($_.Exception.Message)" "WARN"
    }
}

function Rotate-LogsIfNeeded {
    $today = (Get-Date).Date
    if ($LastDailyRotation -and $LastDailyRotation -eq $today) { return }

    $retentionDays = [int]$config.LogRetentionDays

    foreach ($file in @($MainLog, $MetricLog)) {
        if (Test-Path $file) {
            $stamp = Get-Date -Format "yyyyMMdd"
            $archive = "{0}.{1}" -f $file, $stamp
            if (!(Test-Path $archive)) {
                Copy-Item -Path $file -Destination $archive -Force
                Clear-Content -Path $file
            }
        }
    }

    Get-ChildItem -Path $LogDir -File | Where-Object {
        $_.LastWriteTime -lt (Get-Date).AddDays(-$retentionDays)
    } | Remove-Item -Force -ErrorAction SilentlyContinue

    $script:LastDailyRotation = $today
}

function Test-ServerRunning {
    param([string]$ProcessName)
    $procs = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($procs) { return ($procs | Select-Object -First 1) }
    return $null
}

function Trim-RestartWindow {
    param([System.Collections.Generic.List[datetime]]$RestartTimes)
    $cutoff = (Get-Date).AddMinutes(-[int]$config.RestartWindowMinutes)
    for ($i = $RestartTimes.Count - 1; $i -ge 0; $i--) {
        if ($RestartTimes[$i] -lt $cutoff) { $RestartTimes.RemoveAt($i) }
    }
}

function Can-RestartServer {
    param([hashtable]$State)
    if ($State.CooldownUntil -and (Get-Date) -lt $State.CooldownUntil) { return $false }
    Trim-RestartWindow -RestartTimes $State.RestartTimes
    if ($State.RestartTimes.Count -ge [int]$config.MaxRestartsInWindow) {
        $State.CooldownUntil = (Get-Date).AddMinutes([int]$config.CooldownMinutes)
        return $false
    }
    return $true
}

function Start-ManagedServer {
    param(
        [hashtable]$Server,
        [hashtable]$State,
        [string]$Reason
    )

    if (!(Test-Path $Server.StartScript)) {
        Write-Log "$($Server.Name): start script missing at $($Server.StartScript)" "ERROR"
        Invoke-DiscordWebhook -Title "$($Server.Name) start failed" -Description "Start script missing at `"$($Server.StartScript)`"." -Color 15158332
        return
    }

    if (!(Can-RestartServer -State $State)) {
        $msg = "$($Server.Name): restart limit reached. Cooldown until $($State.CooldownUntil)"
        Write-Log $msg "WARN"
        Invoke-DiscordWebhook -Title "$($Server.Name) restart protection" -Description $msg -Color 16776960
        Save-State
        return
    }

    try {
        $State.RestartTimes.Add((Get-Date))
        $State.RestartCount++
        Write-Log "$($Server.Name): starting. Reason: $Reason"
        Invoke-DiscordWebhook -Title "$($Server.Name) starting" -Description "Reason: $Reason" -Color 5763719

        Start-Process -FilePath "cmd.exe" `
            -ArgumentList "/c `"$($Server.StartScript)`"" `
            -WorkingDirectory $Server.WorkingDirectory `
            -WindowStyle Normal | Out-Null

        Start-Sleep -Seconds $Server.StartGraceSeconds

        $realProc = Test-ServerRunning -ProcessName $Server.ProcessName
        if ($realProc) {
            $State.LastKnownRunningPid = $realProc.Id
            Write-Log "$($Server.Name): running with PID $($realProc.Id)"
            Invoke-DiscordWebhook -Title "$($Server.Name) running" -Description "PID: $($realProc.Id)" -Color 3066993
        }
        else {
            Write-Log "$($Server.Name): start command ran but process not detected yet" "WARN"
            Invoke-DiscordWebhook -Title "$($Server.Name) start uncertain" -Description "Start command ran, but process was not detected yet." -Color 16776960
        }
        Save-State
    }
    catch {
        Write-Log "$($Server.Name): start failed - $($_.Exception.Message)" "ERROR"
        Invoke-DiscordWebhook -Title "$($Server.Name) start failed" -Description $_.Exception.Message -Color 15158332
        Save-State
    }
}

function Update-RustServer {
    if (-not $config.RustAutoUpdate.Enabled) { return }

    $steamCmdPath = $config.RustAutoUpdate.SteamCmdPath
    if (!(Test-Path $steamCmdPath)) {
        Write-Log "Rust update skipped: SteamCMD not found at $steamCmdPath" "WARN"
        return
    }

    try {
        Write-Log "Rust: running SteamCMD update"
        Invoke-DiscordWebhook -Title "Rust update started" -Description "SteamCMD update check is running." -Color 3447003

        $args = @(
            "+force_install_dir", $config.RustAutoUpdate.InstallDir,
            "+login", "anonymous",
            "+app_update", "$($config.RustAutoUpdate.AppId)", "validate",
            "+quit"
        )

        $proc = Start-Process -FilePath $steamCmdPath -ArgumentList $args -Wait -PassThru -NoNewWindow
        Write-Log "Rust: SteamCMD finished with exit code $($proc.ExitCode)"
        Invoke-DiscordWebhook -Title "Rust update finished" -Description "SteamCMD exit code: $($proc.ExitCode)" -Color 3066993
    }
    catch {
        Write-Log "Rust update failed: $($_.Exception.Message)" "ERROR"
        Invoke-DiscordWebhook -Title "Rust update failed" -Description $_.Exception.Message -Color 15158332
    }
}

function Get-ProcessMetrics {
    param([int]$Pid)
    try {
        $perf = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process | Where-Object { $_.IDProcess -eq $Pid } | Select-Object -First 1
        if ($perf) {
            return @{
                CpuPercent     = [int]$perf.PercentProcessorTime
                WorkingSetMB   = [math]::Round(($perf.WorkingSetPrivate / 1MB), 2)
                PrivateBytesMB = [math]::Round(($perf.PrivateBytes / 1MB), 2)
                ThreadCount    = [int]$perf.ThreadCount
                HandleCount    = [int]$perf.HandleCount
            }
        }
    }
    catch {}
    return $null
}

function Log-Metrics {
    foreach ($server in $Servers) {
        $proc = Test-ServerRunning -ProcessName $server.ProcessName
        if ($proc) {
            $metrics = Get-ProcessMetrics -Pid $proc.Id
            if ($metrics) {
                $line = "[{0}] {1} PID={2} CPU={3}% WS={4}MB Private={5}MB Threads={6} Handles={7}" -f `
                    (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),
                    $server.Name,
                    $proc.Id,
                    $metrics.CpuPercent,
                    $metrics.WorkingSetMB,
                    $metrics.PrivateBytesMB,
                    $metrics.ThreadCount,
                    $metrics.HandleCount
                Add-Content -Path $MetricLog -Value $line
            }
        }
    }
}

function Initialize-Servers {
    foreach ($server in $Servers) {
        $existing = Test-ServerRunning -ProcessName $server.ProcessName
        if ($existing) {
            $ServerState[$server.Name].LastKnownRunningPid = $existing.Id
            Write-Log "$($server.Name): already running with PID $($existing.Id)"
        }
        else {
            Start-ManagedServer -Server $server -State $ServerState[$server.Name] -Reason "Not running at watchdog startup"
        }
    }
}

Rotate-LogsIfNeeded
Load-State

Write-Log "============================================================"
Write-Log "Watchdog starting"
Write-Log "Config loaded from $ConfigPath"
Write-Log "Boot delay: $($config.BootDelaySeconds) seconds"
Start-Sleep -Seconds ([int]$config.BootDelaySeconds)

if ($config.RustAutoUpdate.Enabled) {
    Update-RustServer
    if ($ServerState.ContainsKey("Rust")) {
        $ServerState["Rust"].LastUpdateCheck = Get-Date
        Save-State
    }
}

Initialize-Servers

while ($true) {
    Rotate-LogsIfNeeded

    foreach ($server in $Servers) {
        $state = $ServerState[$server.Name]
        $runningProc = Test-ServerRunning -ProcessName $server.ProcessName

        if ($server.IsRust -and $config.RustAutoUpdate.Enabled) {
            $updateIntervalHours = [int]$config.RustAutoUpdate.UpdateIntervalHours
            $shouldUpdate = $false

            if (-not $state.LastUpdateCheck) {
                $shouldUpdate = $true
            }
            elseif ((Get-Date) -ge $state.LastUpdateCheck.AddHours($updateIntervalHours)) {
                $shouldUpdate = $true
            }

            if ($shouldUpdate) {
                if ($config.RustAutoUpdate.OnlyUpdateWhenOffline) {
                    if (-not $runningProc) {
                        Update-RustServer
                        $state.LastUpdateCheck = Get-Date
                        Save-State
                    }
                }
                else {
                    Update-RustServer
                    $state.LastUpdateCheck = Get-Date
                    Save-State
                }
            }
        }

        if ($runningProc) {
            if ($state.LastKnownRunningPid -ne $runningProc.Id) {
                Write-Log "$($server.Name): PID changed to $($runningProc.Id)"
                $state.LastKnownRunningPid = $runningProc.Id
                Save-State
            }
        }
        else {
            if ($state.LastKnownRunningPid) {
                $state.LastExitDetectedAt = Get-Date
                Write-Log "$($server.Name): crash or exit detected. Previous PID was $($state.LastKnownRunningPid)" "WARN"
                Invoke-DiscordWebhook -Title "$($server.Name) stopped" -Description "Unexpected stop detected. Attempting restart." -Color 15158332
                $state.LastKnownRunningPid = $null
                Save-State
            }
            else {
                Write-Log "$($server.Name): not running"
            }

            Start-ManagedServer -Server $server -State $state -Reason "Crash detected or process missing"
        }
    }

    Log-Metrics
    Start-Sleep -Seconds ([int]$config.CheckIntervalSeconds)
}
