# run.ps1
# Usage: Right-click → "Run with PowerShell" (or run in a PowerShell window)
# Optionally pass a different tar as the first arg: .\run-immgent.ps1 myapp.tar

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ---- config you can tweak ----
# If an argument is provided, use that as the tar; otherwise default:
$TAR      = $(if ($args.Count -ge 1) { $args[0] } else { "immgent_app1-app_latest.tar" })
$APP_NAME = "immgent_app1"                           # container name
$HOST_PORT = $(if ($env:PORT) { $env:PORT } else { 3838 })
$OPEN_PATH = "/"                                     # change to "/app/" if needed
# Optional resource knobs (Docker Desktop → Settings → Resources must allow these)
$MEM   = "24g"
$SHM   = "2g"
$NOFILE = "1048576"
# --------------------------------

# Ensure we run from this script's folder
if ($PSScriptRoot) { Set-Location -Path $PSScriptRoot }

# Check Docker availability
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Host "Docker is not installed or not running. Install/start Docker Desktop first." -ForegroundColor Red
  exit 1
}

if (-not (Test-Path -LiteralPath $TAR)) {
  Write-Host "File not found: $TAR" -ForegroundColor Red
  exit 1
}

Write-Host "Loading image from: $TAR"

# --- Accurate progress bar while streaming tar -> docker load ---
# We feed the tar to 'docker load' via STDIN and update Write-Progress from bytes copied.
$tarInfo = Get-Item -LiteralPath $TAR
$inStream = [System.IO.File]::OpenRead($tarInfo.FullName)

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "docker"
$psi.Arguments = "load"
$psi.UseShellExecute = $false
$psi.RedirectStandardInput  = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$proc = [System.Diagnostics.Process]::Start($psi)

$buffer = New-Object byte[] 1048576   # 1 MB chunks
[long]$totalRead = 0
$len = $tarInfo.Length
$sw = [System.Diagnostics.Stopwatch]::StartNew()

try {
  while (($n = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
    $proc.StandardInput.BaseStream.Write($buffer, 0, $n)
    $proc.StandardInput.BaseStream.Flush()
    $totalRead += $n

    $pct = if ($len -gt 0) { [math]::Round(($totalRead * 100.0) / $len, 1) } else { 0 }
    $mbRead = [math]::Round($totalRead / 1MB)
    $mbLen  = if ($len -gt 0) { [math]::Round($len / 1MB) } else { 0 }
    $rateMBs = if ($sw.Elapsed.TotalSeconds -gt 0) { [math]::Round(($totalRead/1MB) / $sw.Elapsed.TotalSeconds, 1) } else { 0 }

    Write-Progress -Activity "Loading Docker image" `
                   -Status  "$pct%  ($mbRead / $mbLen MB)  ~${rateMBs}MB/s" `
                   -PercentComplete $pct
  }
} finally {
  $inStream.Close()
  $proc.StandardInput.Close()
}

$proc.WaitForExit()
Write-Progress -Activity "Loading Docker image" -Completed

# Capture output (e.g., "Loaded image: repo/name:tag")
$stdout = $proc.StandardOutput.ReadToEnd()
$stderr = $proc.StandardError.ReadToEnd()
if ($proc.ExitCode -ne 0) {
  Write-Host "docker load failed:" -ForegroundColor Red
  if ($stderr) { Write-Host $stderr -ForegroundColor Red }
  exit 1
}
if ($stdout) { Write-Host $stdout }

# Parse image name
$image = $null
$match = [regex]::Match($stdout, 'Loaded image:\s*(.+)$', 'IgnoreCase, Multiline')
if ($match.Success) { $image = $match.Groups[1].Value.Trim() }
if (-not $image) {
  $image = "immgent_app1-app:latest"   # fallback if tar saved from image ID
  Write-Host "Could not parse image name from tar. Falling back to: $image" -ForegroundColor Yellow
}

# Clean up any prior container
& docker rm -f $APP_NAME 2>$null | Out-Null

Write-Host "Starting container '$APP_NAME' from image '$image' ..."
# Build docker run args list
$runArgs = @(
  "run","-d","--rm",
  "--name", $APP_NAME,
  "--platform=linux/amd64",          # keep for Apple Silicon / cross-arch hosts pulling x86_64 image
  "-p", "$HOST_PORT`:3838",
  "--memory=$MEM",
  "--shm-size=$SHM",
  "--ulimit", "nofile=$NOFILE",
  "-e","SHINY_LOG_STDOUT=1",
  "-e","SHINY_LOG_STDERR=1",
  $image
)

# Launch container
$containerId = & docker @runArgs
if ($LASTEXITCODE -ne 0) {
  Write-Host "docker run failed" -ForegroundColor Red
  exit 1
}

# Wait for the app to come up
$baseUrl = "http://localhost:$HOST_PORT$OPEN_PATH"
Write-Host "Waiting for Shiny at $baseUrl ..."
$ok = $false
for ($i=0; $i -lt 60; $i++) {
  try {
    # -UseBasicParsing for older PS; -TimeoutSec to avoid long stalls
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Uri $baseUrl | Out-Null
    $ok = $true
    break
  } catch {
    Start-Sleep -Seconds 1
  }
}

# Open default browser
Start-Process $baseUrl

if (-not $ok) {
  Write-Host "Warning: the app is not reachable yet, but the container is running (ID: $containerId)." -ForegroundColor Yellow
  Write-Host "You can check logs with: docker logs -f $APP_NAME"
  exit 0
}

Write-Host "Streaming logs (Ctrl+C to stop viewing; container keeps running) ..."
# Stream logs (this will keep the console attached)
& docker logs -f $APP_NAME
