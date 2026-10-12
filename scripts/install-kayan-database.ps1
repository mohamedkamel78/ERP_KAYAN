# Prepare the PostgreSQL runtime in ProgramData so the database Windows
# service is independent of the application install folder and survives
# application updates/uninstall. Never replace an existing runtime/data set.
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$AppDir)

$ErrorActionPreference = "Stop"
$logDir = Join-Path $env:ProgramData "KAYAN-ERP"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stdout = Join-Path $logDir "installer-db-setup.log"
$stderr = Join-Path $logDir "installer-db-setup-error.log"
$manager = Join-Path $AppDir "backend\scripts\manage-kayan-db.ps1"
$packagePgRoot = Join-Path $AppDir "backend\pg"
$runtimeRoot = Join-Path $logDir "pgsql"
$pgDir = Join-Path $runtimeRoot "bin"
$dataDir = Join-Path $logDir "pgdata"
$runtimeVersion = Join-Path $dataDir "PG_VERSION"
if (-not (Test-Path $manager)) { throw ("The packaged PostgreSQL provisioner is missing: " + $manager) }
if (-not (Test-Path (Join-Path $packagePgRoot "bin\initdb.exe"))) { throw ("The packaged PostgreSQL server binaries are missing: " + $packagePgRoot) }

if (-not (Test-Path (Join-Path $pgDir "initdb.exe"))) {
  if (Test-Path $runtimeVersion) {
    throw "Existing KAYAN database data was found but its persistent PostgreSQL runtime is missing. Setup stopped without touching the existing data."
  }
  foreach ($relative in @("bin\initdb.exe", "bin\pg_ctl.exe", "bin\postgres.exe", "share\postgres.bki", "lib\plpgsql.dll")) {
    if (-not (Test-Path (Join-Path $packagePgRoot $relative))) { throw ("PostgreSQL package is incomplete: " + $relative) }
  }
  New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
  New-Item -ItemType Directory -Force -Path $pgDir | Out-Null
  Copy-Item (Join-Path $packagePgRoot "bin\*") $pgDir -Recurse -Force
  Copy-Item (Join-Path $packagePgRoot "share") (Join-Path $runtimeRoot "share") -Recurse -Force
  Copy-Item (Join-Path $packagePgRoot "lib") (Join-Path $runtimeRoot "lib") -Recurse -Force
}
if (-not (Test-Path (Join-Path $pgDir "initdb.exe"))) { throw "Persistent PostgreSQL runtime is still incomplete after setup." }
if (-not (Test-Path (Join-Path $runtimeRoot "share\postgres.bki"))) { throw "Persistent PostgreSQL share data is missing." }

$powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$arguments = '-ExecutionPolicy Bypass -NoProfile -File "' + $manager + '" -Action install -Port 5433 -DataDir "' + $dataDir + '" -PgBinDir "' + $pgDir + '"'
$process = Start-Process -FilePath $powershell -ArgumentList $arguments -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
if ($process.ExitCode -ne 0) { throw ("Database provisioning failed with exit code " + $process.ExitCode + ". Read " + $stderr) }
$settings = Join-Path $logDir "kayan.env"
if (-not (Test-Path $settings)) { throw ("The protected runtime settings were not written. Read " + $stdout + " and " + $stderr) }
$service = Get-Service -Name "KAYAN_PostgreSQL" -ErrorAction SilentlyContinue
if (-not $service) { throw ("KAYAN_PostgreSQL was not registered. Read " + $stdout + " and " + $stderr) }
if ($service.Status -ne "Running") { throw ("KAYAN_PostgreSQL did not reach Running state. Read " + $stdout + " and " + $stderr) }
$serviceInfo = Get-CimInstance Win32_Service -Filter "Name='KAYAN_PostgreSQL'" -ErrorAction Stop
if ($serviceInfo.PathName -notlike "*$runtimeRoot*") { throw ("KAYAN_PostgreSQL does not point to its persistent ProgramData runtime: " + $serviceInfo.PathName) }
Write-Host "KAYAN database provisioning completed successfully; its runtime and data survive app uninstall."
