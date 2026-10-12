# Runs the real Windows installer on the CI runner and verifies the local API.
[CmdletBinding()]
param([string]$SetupPath = "build\desktop\KAYAN-Setup.exe")

$ErrorActionPreference = "Stop"
$setup = (Resolve-Path $SetupPath).Path
$installLog = Join-Path $env:TEMP "kayan-setup-smoke.log"
$install = Start-Process -FilePath $setup -ArgumentList @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", ("/LOG=" + $installLog)) -Wait -PassThru
$dbLog = Join-Path $env:ProgramData "KAYAN-ERP\installer-db-setup.log"
$dbError = Join-Path $env:ProgramData "KAYAN-ERP\installer-db-setup-error.log"
if ($install.ExitCode -ne 0) {
  $details = @()
  foreach ($path in @($dbLog, $dbError, $installLog)) { if (Test-Path $path) { $details += ("--- " + $path + " ---"); $details += Get-Content $path -Tail 80 } }
  throw ("KAYAN-Setup.exe failed with exit code " + $install.ExitCode + [Environment]::NewLine + ($details -join [Environment]::NewLine))
}

$service = Get-Service -Name "KAYAN_PostgreSQL" -ErrorAction SilentlyContinue
if (-not $service) {
  $details = @()
  foreach ($path in @($dbLog, $dbError, $installLog)) { if (Test-Path $path) { $details += ("--- " + $path + " ---"); $details += Get-Content $path -Tail 80 } }
  throw ("KAYAN_PostgreSQL was not installed as a persistent service." + [Environment]::NewLine + ($details -join [Environment]::NewLine))
}
if ($service.Status -ne "Running") { throw "The installer did not start KAYAN_PostgreSQL." }
$settings = Join-Path $env:ProgramData "KAYAN-ERP\kayan.env"
if (-not (Test-Path $settings)) { throw "The installer did not write the shared runtime settings file." }

Get-Content $settings | ForEach-Object {
  $line = $_.Trim()
  if ($line -and -not $line.StartsWith("#") -and $line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
    $key = $Matches[1]
    $value = $Matches[2].Trim().Trim('"')
    Set-Item -Path ("Env:" + $key) -Value $value
  }
}

$backend = Join-Path $env:ProgramFiles "KAYAN ERP\backend"
$node = Join-Path $backend "node\node.exe"
if (-not (Test-Path $node)) { throw "The bundled Node runtime was not installed." }
$api = $null
try {
  $prepare = Start-Process -FilePath $node -ArgumentList @("scripts\prepare-database.mjs") -WorkingDirectory $backend -Wait -PassThru -NoNewWindow
  if ($prepare.ExitCode -ne 0) { throw ("Database preparation failed with exit code " + $prepare.ExitCode) }

  $stdout = Join-Path $env:TEMP "kayan-installer-smoke-stdout.log"
  $stderr = Join-Path $env:TEMP "kayan-installer-smoke-stderr.log"
  $api = Start-Process -FilePath $node -ArgumentList @("dist\src\main.js") -WorkingDirectory $backend -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $health = $null
  for ($attempt = 0; $attempt -lt 60; $attempt++) {
    if ($api.HasExited) {
      $out = if (Test-Path $stdout) { Get-Content $stdout -Raw } else { "" }
      $err = if (Test-Path $stderr) { Get-Content $stderr -Raw } else { "" }
      throw ("The packaged API exited before becoming healthy." + [Environment]::NewLine + $out + [Environment]::NewLine + $err)
    }
    try {
      $health = Invoke-RestMethod -Uri "http://127.0.0.1:3000/api/v1/health" -TimeoutSec 2
      if ($health.status -eq "ok" -and $health.database -eq "up") { break }
    } catch { }
    Start-Sleep -Seconds 1
  }
  if (-not $health -or $health.status -ne "ok" -or $health.database -ne "up") {
    $out = if (Test-Path $stdout) { Get-Content $stdout -Raw } else { "" }
    $err = if (Test-Path $stderr) { Get-Content $stderr -Raw } else { "" }
    throw ("The installed API did not report status=ok and database=up." + [Environment]::NewLine + $out + [Environment]::NewLine + $err)
  }
  Write-Host "PASS: bundled Node API and PostgreSQL returned status=ok, database=up."

  # Stop the manually launched API and prove the actual packaged Flutter client
  # starts its own backend. This directly covers the original cannot-connect
  # failure mode instead of testing Node in isolation.
  if ($api -and -not $api.HasExited) { Stop-Process -Id $api.Id -Force -ErrorAction SilentlyContinue }
  if ($api) { try { Wait-Process -Id $api.Id -Timeout 10 -ErrorAction SilentlyContinue } catch { } }
  $api = $null
  Start-Sleep -Seconds 2
  $clientPath = Join-Path $env:ProgramFiles "KAYAN ERP\erp_kayan.exe"
  if (-not (Test-Path $clientPath)) { throw ("The installed KAYAN client is missing: " + $clientPath) }
  $client = Start-Process -FilePath $clientPath -PassThru
  $clientHealth = $null
  try {
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
      if ($client.HasExited) { throw ("The installed KAYAN client exited with code " + $client.ExitCode + " before starting its backend.") }
      try {
        $clientHealth = Invoke-RestMethod -Uri "http://127.0.0.1:3000/api/v1/health" -TimeoutSec 2
        if ($clientHealth.status -eq "ok" -and $clientHealth.database -eq "up") { break }
      } catch { }
      Start-Sleep -Seconds 1
    }
    if (-not $clientHealth -or $clientHealth.status -ne "ok" -or $clientHealth.database -ne "up") {
      $logDir = Join-Path $env:APPDATA "KAYAN-ERP"
      $details = @()
      if (Test-Path $logDir) {
        Get-ChildItem $logDir -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Length -lt 2MB } | ForEach-Object {
          $details += ("--- " + $_.FullName + " ---")
          $details += Get-Content $_.FullName -Tail 80 -ErrorAction SilentlyContinue
        }
      }
      throw ("The actual installed client did not start a healthy local server after 60 seconds." + [Environment]::NewLine + ($details -join [Environment]::NewLine))
    }
    Write-Host "PASS: launching installed erp_kayan.exe by itself started the local API and health check passed."
  } finally {
    if ($client -and -not $client.HasExited) {
      $null = $client.CloseMainWindow()
      try { Wait-Process -Id $client.Id -Timeout 10 -ErrorAction SilentlyContinue } catch { }
      if (-not $client.HasExited) { Stop-Process -Id $client.Id -Force -ErrorAction SilentlyContinue }
    }
  }
} finally {
  if ($api -and -not $api.HasExited) { Stop-Process -Id $api.Id -Force -ErrorAction SilentlyContinue }
  $installNode = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.ExecutablePath -eq $node -and $_.CommandLine -like "*$backend*" -and $_.CommandLine -like "*dist*src*main.js*" }
  foreach ($process in $installNode) { Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue }
  Stop-Service -Name "KAYAN_PostgreSQL" -Force -ErrorAction SilentlyContinue
}
