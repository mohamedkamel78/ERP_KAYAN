<#
.SYNOPSIS
  Manages the dedicated KAYAN PostgreSQL database instance on Windows.
  Ensures clean, zero-configuration setup without conflicting with other
  PostgreSQL instances.

.DESCRIPTION
  Actions:
    install    Initializes pgdata (if needed), registers Windows Service
               'KAYAN_PostgreSQL' on port 5433, starts it, provisions
               erp_app role & erp_kayan database, writes kayan.env.
    start      Starts the KAYAN_PostgreSQL service or daemon.
    stop       Stops the KAYAN_PostgreSQL service or daemon.
    status     Checks service status and TCP port 5433 liveness.
    uninstall  Stops and unregisters the service, PRESERVING data in pgdata.
    purge      Deletes pgdata (only when -Force is explicitly specified).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\manage-kayan-db.ps1 -Action install
#>

[CmdletBinding()]
param(
  [ValidateSet('install', 'start', 'stop', 'status', 'uninstall', 'purge')]
  [string]$Action = 'status',
  [string]$Port = '5433',
  [string]$ServiceName = 'KAYAN_PostgreSQL',
  [string]$DataDir = '',
  [string]$PgBinDir = '',
  [string]$AppPassword = '',
  [string]$PostgresPassword = '',
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Get-KayanDataDir {
  if ($DataDir -and $DataDir.Trim().Length -gt 0) { return $DataDir }
  if ($env:ProgramData) {
    return Join-Path $env:ProgramData "KAYAN-ERP\pgdata"
  }
  return Join-Path $env:LOCALAPPDATA "KAYAN-ERP\pgdata"
}

function Find-PgBin {
  if ($PgBinDir -and (Test-Path (Join-Path $PgBinDir "initdb.exe"))) {
    return $PgBinDir
  }

  $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
  $root = Split-Path -Parent $scriptDir

  $candidates = @(
    (Join-Path $env:ProgramData "KAYAN-ERP\pgsql\bin"),
    (Join-Path $root "backend\pg\bin"),
    (Join-Path $root "backend\pg"),
    (Join-Path $root "backend\pgsql\bin"),
    "${env:LOCALAPPDATA}\kayan-tools\pgsql\bin",
    "${env:ProgramFiles}\KAYAN ERP\backend\pg\bin",
    "${env:ProgramFiles}\KAYAN ERP\backend\pg",
    "${env:ProgramFiles(x86)}\KAYAN ERP\backend\pg\bin",
    "${env:ProgramFiles(x86)}\KAYAN ERP\backend\pg"
  )

  # Check standard PostgreSQL installs as secondary fallback
  foreach ($ver in 18..14) {
    $candidates += "${env:ProgramFiles}\PostgreSQL\$ver\bin"
    $candidates += "${env:ProgramFiles(x86)}\PostgreSQL\$ver\bin"
  }

  foreach ($dir in $candidates) {
    if ($dir -and (Test-Path (Join-Path $dir "initdb.exe")) -and (Test-Path (Join-Path $dir "pg_ctl.exe"))) {
      return $dir
    }
  }

  # Last resort: on PATH
  $cmd = Get-Command "initdb.exe" -ErrorAction SilentlyContinue
  if ($cmd) { return Split-Path -Parent $cmd.Source }

  return $null
}

function Test-PortListening([int]$p) {
  try {
    $client = [System.Net.Sockets.TcpClient]::new()
    $async = $client.BeginConnect("127.0.0.1", $p, $null, $null)
    $ok = $async.AsyncWaitHandle.WaitOne(1000)
    if ($ok -and $client.Connected) {
      $client.EndConnect($async)
      $client.Close()
      return $true
    }
    $client.Close()
    return $false
  } catch {
    return $false
  }
}

$pgDir = Find-PgBin
$targetDataDir = Get-KayanDataDir
if (-not $PostgresPassword -and $env:KAYAN_POSTGRES_ADMIN_PASSWORD) { $PostgresPassword = $env:KAYAN_POSTGRES_ADMIN_PASSWORD }
$script:KayanPostgresConfigChanged = $false

switch ($Action) {
  'status' {
    Write-Host "KAYAN Database Status Check (Port $Port)" -ForegroundColor Cyan
    $listening = Test-PortListening ([int]$Port)
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
      Write-Host "  Service '$ServiceName': $($svc.Status)"
    } else {
      Write-Host "  Service '$ServiceName': Not registered"
    }
    if ($listening) {
      Write-Host "  TCP Port $Port : LISTENING (Ready)" -ForegroundColor Green
      exit 0
    } else {
      Write-Host "  TCP Port $Port : Not listening" -ForegroundColor Yellow
      exit 1
    }
  }

  'install' {
    Write-Host "=== Setting up Dedicated KAYAN PostgreSQL Instance ===" -ForegroundColor Cyan
    if (-not $pgDir) {
      Write-Error "PostgreSQL tools (initdb.exe, pg_ctl.exe) not found. Run installer or scripts\install-postgres-portable.bat."
      exit 1
    }
    Write-Host "  Using PostgreSQL binaries from: $pgDir"
    Write-Host "  Target data directory: $targetDataDir"
    Write-Host "  Dedicated port: $Port"

    $initDb = Join-Path $pgDir "initdb.exe"
    $pgCtl = Join-Path $pgDir "pg_ctl.exe"
    $psql = Join-Path $pgDir "psql.exe"

    # 1. Initialize data cluster if not present
    $versionFile = Join-Path $targetDataDir "PG_VERSION"
    if (-not (Test-Path $versionFile)) {
      Write-Host "  Initializing new database cluster in $targetDataDir..." -ForegroundColor Cyan
      New-Item -ItemType Directory -Force -Path $targetDataDir | Out-Null

      $shareDir = Join-Path (Split-Path -Parent $pgDir) "share"
      if (-not (Test-Path $shareDir)) {
        $shareDir = Join-Path $pgDir "share"
      }

      $initArgs = @("-D", $targetDataDir, "-U", "postgres", "-A", "trust", "-E", "UTF8", "--locale=C")
      if (Test-Path $shareDir) {
        $initArgs += @("-L", $shareDir)
      }

      & $initDb @initArgs
      if ($LASTEXITCODE -ne 0) {
        Write-Error "initdb failed with exit code $LASTEXITCODE."
        exit 1
      }
      Write-Host "  [OK] Database cluster initialized." -ForegroundColor Green
    } else {
      Write-Host "  [OK] Existing database cluster found, preserving all data." -ForegroundColor Green
    }

    # 2. Configure port in postgresql.conf
    $confFile = Join-Path $targetDataDir "postgresql.conf"
    if (Test-Path $confFile) {
      $conf = Get-Content $confFile -Raw
      $beforeConfig = $conf
      $conf = [regex]::Replace($conf, '(?m)^[ \t]*#?[ \t]*port[ \t]*=[^\r\n]*$', "port = $Port")
      if ($conf -notmatch '(?m)^[ \t]*port[ \t]*=') { $conf += [Environment]::NewLine + "port = $Port" + [Environment]::NewLine }
      # Keep PostgreSQL loopback-only; clients must reach the API, not the DB directly.
      $conf = [regex]::Replace($conf, "(?m)^[ \t]*#?[ \t]*listen_addresses[ \t]*=[^\r\n]*$", "listen_addresses = '127.0.0.1'")
      if ($conf -notmatch "(?m)^[ \t]*listen_addresses[ \t]*=") { $conf += [Environment]::NewLine + "listen_addresses = '127.0.0.1'" + [Environment]::NewLine }
      if ($conf -ne $beforeConfig) { $script:KayanPostgresConfigChanged = $true }
      Set-Content -Path $confFile -Value $conf -Encoding UTF8
    }

    # 3. Register and start a persistent Windows service. A background pg_ctl
    # process is not sufficient: it would disappear on reboot.
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) {
      Write-Host "  Registering Windows Service '$ServiceName' on port $Port..." -ForegroundColor Cyan
      & $pgCtl register -N $ServiceName -D $targetDataDir -o "-p $Port" -S auto
      $registerExitCode = $LASTEXITCODE
      $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
      if (-not $svc) {
        Write-Host "  pg_ctl register returned $registerExitCode; using New-Service fallback." -ForegroundColor Yellow
        $serviceCommand = '"' + $pgCtl + '" runservice -N "' + $ServiceName + '" -D "' + $targetDataDir + '" -o "-p ' + $Port + '"'
        New-Service -Name $ServiceName -DisplayName "KAYAN ERP PostgreSQL" -Description "Dedicated local PostgreSQL database for KAYAN ERP." -BinaryPathName $serviceCommand -StartupType Automatic | Out-Null
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
      }
    }
    if (-not $svc) { throw "Could not register the persistent Windows service '$ServiceName'." }
    Set-Service -Name $ServiceName -StartupType Automatic
    if ($svc.Status -ne "Running") { Start-Service -Name $ServiceName -ErrorAction Stop }
    $attempts = 0
    while (-not (Test-PortListening ([int]$Port)) -and $attempts -lt 30) {
      Start-Sleep -Seconds 1
      $attempts++
    }
    if (-not (Test-PortListening ([int]$Port))) { throw "Windows service '$ServiceName' did not start PostgreSQL on port $Port." }
    Write-Host "  [OK] Persistent service '$ServiceName' is running on 127.0.0.1:$Port." -ForegroundColor Green

    # 4. Provision erp_app role and erp_kayan database
    if (-not $AppPassword) {
      $AppPassword = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 28 | ForEach-Object {[char]$_})
    }

    $escapedPw = $AppPassword.Replace("'", "''")
    if ($PostgresPassword) { $env:PGPASSWORD = $PostgresPassword }
    $checkRole = & $psql -h 127.0.0.1 -p $Port -U postgres -d postgres -t -A -c "SELECT 1 FROM pg_roles WHERE rolname='erp_app';" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Cannot authenticate to the PostgreSQL administrator account. Existing data was not changed." }
    if ("$checkRole" -match "1") {
      & $psql -h 127.0.0.1 -p $Port -U postgres -d postgres -c "ALTER ROLE erp_app WITH LOGIN CREATEDB PASSWORD '$escapedPw';" | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "Could not configure the erp_app database role." }
      Write-Host "  [OK] Synchronized password for existing role 'erp_app'." -ForegroundColor Green
    } else {
      & $psql -h 127.0.0.1 -p $Port -U postgres -d postgres -c "CREATE ROLE erp_app WITH LOGIN CREATEDB PASSWORD '$escapedPw';" | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "Could not create the erp_app database role." }
      Write-Host "  [OK] Created database role 'erp_app'." -ForegroundColor Green
    }

    $checkDb = & $psql -h 127.0.0.1 -p $Port -U postgres -d postgres -t -A -c "SELECT 1 FROM pg_database WHERE datname='erp_kayan';" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Could not verify the erp_kayan database." }
    if ("$checkDb" -notmatch "1") {
      & $psql -h 127.0.0.1 -p $Port -U postgres -d postgres -c "CREATE DATABASE erp_kayan OWNER erp_app;" | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "Could not create the erp_kayan database." }
      Write-Host "  [OK] Created database 'erp_kayan'." -ForegroundColor Green
    } else {
      Write-Host "  [OK] Existing database 'erp_kayan' verified (data preserved)." -ForegroundColor Green
    }

    # 5. Persist settings in the machine configuration directory.
    # The installer runs elevated, while the app is launched as the normal
    # user. ProgramData gives both processes one stable path; lock the file
    # down to the installing user's SID, SYSTEM and local Administrators.
    $kayanDir = Join-Path $env:ProgramData "KAYAN-ERP"
    New-Item -ItemType Directory -Force -Path $kayanDir | Out-Null
    $envFile = Join-Path $kayanDir "kayan.env"

    $jwtAccess = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 48 | ForEach-Object {[char]$_})
    $jwtRefresh = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 48 | ForEach-Object {[char]$_})

    $envContent = @"
# KAYAN ERP - Application Runtime Configuration
# Generated automatically by KAYAN Setup.

HOST="0.0.0.0"
PORT=3000
DATABASE_URL="postgresql://erp_app:$AppPassword@127.0.0.1:$Port/erp_kayan?schema=public"
ADMIN_DATABASE_URL="postgresql://postgres:$PostgresPassword@127.0.0.1:$Port/postgres"
JWT_ACCESS_SECRET="$jwtAccess"
JWT_REFRESH_SECRET="$jwtRefresh"
JWT_ACCESS_TTL=900
JWT_REFRESH_TTL=1209600
"@
    Set-Content -Path $envFile -Value $envContent -Encoding UTF8

    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls.exe $envFile /inheritance:r /grant:r "*$($sid):(R)" "*S-1-5-18:(F)" "*S-1-5-32-544:(F)" | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "Could not secure the KAYAN runtime configuration file ACL."
    }
    Write-Host "  [OK] Persisted protected runtime configuration to: $envFile" -ForegroundColor Green

    Write-Host "`n=== Database setup finished successfully ===" -ForegroundColor Green
    exit 0
  }

  'start' {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
      if ($svc.Status -ne 'Running') {
        Start-Service -Name $ServiceName
      }
    } elseif ($pgDir -and (Test-Path $targetDataDir)) {
      $pgCtl = Join-Path $pgDir "pg_ctl.exe"
      & $pgCtl start -D $targetDataDir -o "-p $Port" -w -t 15
    }
  }

  'stop' {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
      if ($svc.Status -ne 'Stopped') {
        Stop-Service -Name $ServiceName -Force
      }
    } elseif ($pgDir -and (Test-Path $targetDataDir)) {
      $pgCtl = Join-Path $pgDir "pg_ctl.exe"
      & $pgCtl stop -D $targetDataDir -m fast
    }
  }

  'uninstall' {
    Write-Host "Stopping and unregistering service '$ServiceName'..."
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
      try { Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue } catch {}
      & sc.exe delete $ServiceName | Out-Null
      Write-Host "  [OK] Service unregistered."
    }
    Write-Host "  Note: User data in $targetDataDir was PRESERVED." -ForegroundColor Green
  }

  'purge' {
    if (-not $Force) {
      Write-Error "Purge requires -Force switch. This will permanently delete all company data in $targetDataDir."
      exit 1
    }
    Write-Host "Purging data directory $targetDataDir..." -ForegroundColor Red
    if (Test-Path $targetDataDir) {
      Remove-Item -Recurse -Force $targetDataDir
      Write-Host "  [OK] Data directory purged."
    }
  }
}
