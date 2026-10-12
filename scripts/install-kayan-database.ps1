# Install the embedded official PostgreSQL distribution as its own persistent Windows service.
# KAYAN-Setup remains the only distributed installer. Existing data/configuration is preserved.
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$AppDir)

$ErrorActionPreference = "Stop"
$logDir = Join-Path $env:ProgramData "KAYAN-ERP"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$packageInstaller = Join-Path $AppDir "backend\pg\postgresql-installer.exe"
$manager = Join-Path $AppDir "backend\scripts\manage-kayan-db.ps1"
$runtimeRoot = Join-Path $logDir "pgsql"
$pgDir = Join-Path $runtimeRoot "bin"
$dataDir = Join-Path $logDir "pgdata"
$settings = Join-Path $logDir "kayan.env"
$runtimeVersion = Join-Path $dataDir "PG_VERSION"
$serviceName = "KAYAN_PostgreSQL"

if (-not (Test-Path $manager)) { throw ("The packaged PostgreSQL manager is missing: " + $manager) }

# A reinstall must never replace runtime files or credentials used by an existing company database.
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
  if (-not (Test-Path $runtimeVersion) -or -not (Test-Path (Join-Path $pgDir "postgres.exe"))) {
    throw "KAYAN_PostgreSQL already exists but its persistent runtime/data is incomplete. Setup stopped without changing company data."
  }
  if (-not (Test-Path $settings)) { throw "Existing KAYAN database data was found but kayan.env is missing. Setup did not regenerate credentials or modify the database." }
  $serviceInfo = Get-CimInstance Win32_Service -Filter "Name='KAYAN_PostgreSQL'" -ErrorAction Stop
  if ($serviceInfo.PathName -notlike "*$runtimeRoot*") { throw ("A service named KAYAN_PostgreSQL exists outside the KAYAN runtime; refusing to replace it: " + $serviceInfo.PathName) }
  if ($service.Status -ne "Running") { Start-Service -Name $serviceName -ErrorAction Stop }
  $tcp = [System.Net.Sockets.TcpClient]::new()
  try {
    $connect = $tcp.BeginConnect("127.0.0.1", 5433, $null, $null)
    if (-not $connect.AsyncWaitHandle.WaitOne(10000)) { throw "Existing KAYAN PostgreSQL service did not listen on port 5433." }
    $tcp.EndConnect($connect)
  } finally { $tcp.Dispose() }
  Write-Host "Existing KAYAN PostgreSQL runtime, service, credentials and company data were preserved."
  exit 0
}
if (Test-Path $runtimeVersion) { throw "Existing KAYAN database data was found without its registered service. Setup stopped without initializing, replacing, or deleting the data." }
if (-not (Test-Path $packageInstaller)) { throw ("The embedded PostgreSQL installer is missing: " + $packageInstaller) }
if ((Get-Item $packageInstaller).Length -lt 20000000) { throw "The embedded PostgreSQL installer is unexpectedly small or incomplete." }
if (Test-Path $runtimeRoot) { Remove-Item -Recurse -Force $runtimeRoot }
New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null

$postgresPassword = [guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N")
$servicePassword = [guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N")
$serviceAccount = "kayanpg" + [guid]::NewGuid().ToString("N").Substring(0, 8)
$installerTrace = Join-Path $logDir "postgresql-installer-trace.log"
$installerStdout = Join-Path $logDir "postgresql-installer-stdout.log"
$installerStderr = Join-Path $logDir "postgresql-installer-stderr.log"
$arguments = '--mode unattended --unattendedmodeui none --prefix "' + $runtimeRoot + '" --datadir "' + $dataDir + '" --serverport 5433 --servicename KAYAN_PostgreSQL --superaccount postgres --superpassword ' + $postgresPassword + ' --serviceaccount ' + $serviceAccount + ' --servicepassword ' + $servicePassword + ' --enable_acledit 1 --install_runtimes yes --disable-components "pgAdmin,stackbuilder" --debugtrace "' + $installerTrace + '"'
Write-Host "Installing the embedded EDB PostgreSQL server as a dedicated KAYAN_PostgreSQL service..."
$installer = Start-Process -FilePath $packageInstaller -ArgumentList $arguments -Wait -PassThru -RedirectStandardOutput $installerStdout -RedirectStandardError $installerStderr
if ($installer.ExitCode -ne 0) {
  $details = @()
  foreach ($log in @($installerStderr, $installerStdout, $installerTrace)) {
    if (Test-Path $log) { $details += ("--- " + $log + " ---"); $details += Get-Content $log -Tail 80 }
  }
  throw ("The embedded PostgreSQL installer failed with exit code " + $installer.ExitCode + "." + [Environment]::NewLine + ($details -join [Environment]::NewLine))
}

$required = @("bin\initdb.exe", "bin\pg_ctl.exe", "bin\postgres.exe", "bin\psql.exe", "bin\pg_dump.exe", "bin\pg_restore.exe", "share\postgres.bki", "share\timezone", "share\timezonesets", "lib\plpgsql.dll")
foreach ($item in $required) {
  if (-not (Test-Path (Join-Path $runtimeRoot $item))) { throw ("PostgreSQL installation completed but required runtime file is missing: " + $item) }
}
if (-not (Test-Path $runtimeVersion)) { throw "PostgreSQL installer returned success but did not initialize the persistent KAYAN data directory." }
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $service) { throw "PostgreSQL installer returned success but did not create the KAYAN_PostgreSQL Windows service." }
if ($service.Status -ne "Running") { Start-Service -Name $serviceName -ErrorAction Stop }

# Provision application credentials and protected runtime configuration.
$env:KAYAN_POSTGRES_ADMIN_PASSWORD = $postgresPassword
$powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$managerStdout = Join-Path $logDir "kayan-db-provision.log"
$managerStderr = Join-Path $logDir "kayan-db-provision-error.log"
$managerArguments = '-ExecutionPolicy Bypass -NoProfile -File "' + $manager + '" -Action install -Port 5433 -DataDir "' + $dataDir + '" -PgBinDir "' + $pgDir + '"'
try {
  $provision = Start-Process -FilePath $powershell -ArgumentList $managerArguments -Wait -PassThru -RedirectStandardOutput $managerStdout -RedirectStandardError $managerStderr
} finally { Remove-Item Env:KAYAN_POSTGRES_ADMIN_PASSWORD -ErrorAction SilentlyContinue }
if ($provision.ExitCode -ne 0) {
  $details = @()
  foreach ($log in @($managerStderr, $managerStdout)) {
    if (Test-Path $log) { $details += ("--- " + $log + " ---"); $details += Get-Content $log -Tail 80 }
  }
  throw ("KAYAN database/credential provisioning failed with exit code " + $provision.ExitCode + "." + [Environment]::NewLine + ($details -join [Environment]::NewLine))
}
if (-not (Test-Path $settings)) { throw "PostgreSQL was installed but protected KAYAN runtime settings were not written." }
$service = Get-Service -Name $serviceName -ErrorAction Stop
if ($service.Status -ne "Running") { throw "KAYAN_PostgreSQL did not reach Running state." }
$serviceInfo = Get-CimInstance Win32_Service -Filter "Name='KAYAN_PostgreSQL'" -ErrorAction Stop
if ($serviceInfo.PathName -notlike "*$runtimeRoot*") { throw ("KAYAN_PostgreSQL is not using the persistent ProgramData runtime: " + $serviceInfo.PathName) }
Write-Host "KAYAN PostgreSQL is installed and running; its service, runtime and data persist after app uninstall."
