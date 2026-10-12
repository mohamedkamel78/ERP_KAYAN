# Runs the database provisioner during installation, captures diagnostics,
# and makes setup fail if the local database and protected settings are not ready.
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$AppDir)

$ErrorActionPreference = "Stop"
$logDir = Join-Path $env:ProgramData "KAYAN-ERP"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stdout = Join-Path $logDir "installer-db-setup.log"
$stderr = Join-Path $logDir "installer-db-setup-error.log"
$manager = Join-Path $AppDir "backend\scripts\manage-kayan-db.ps1"
$pgDir = Join-Path $AppDir "backend\pg"
if (-not (Test-Path $manager)) { throw ("The packaged PostgreSQL provisioner is missing: " + $manager) }
if (-not (Test-Path (Join-Path $pgDir "initdb.exe"))) { throw ("The packaged PostgreSQL server binaries are missing: " + $pgDir) }
$powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$arguments = '-ExecutionPolicy Bypass -NoProfile -File "' + $manager + '" -Action install -Port 5433 -PgBinDir "' + $pgDir + '"'
$process = Start-Process -FilePath $powershell -ArgumentList $arguments -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
if ($process.ExitCode -ne 0) { throw ("Database provisioning failed with exit code " + $process.ExitCode + ". Read " + $stderr) }
$settings = Join-Path $logDir "kayan.env"
if (-not (Test-Path $settings)) { throw ("The protected runtime settings were not written. Read " + $stdout + " and " + $stderr) }
$service = Get-Service -Name "KAYAN_PostgreSQL" -ErrorAction SilentlyContinue
if ($service) {
  if ($service.Status -ne "Running") { throw ("KAYAN_PostgreSQL did not reach Running state. Read " + $stdout + " and " + $stderr) }
} else {
  $listening = Test-NetConnection -ComputerName "127.0.0.1" -Port 5433 -InformationLevel Quiet
  if (-not $listening) { throw ("PostgreSQL was not registered as a service and port 5433 is not listening. Read " + $stdout + " and " + $stderr) }
}
Write-Host "KAYAN database provisioning completed successfully."
