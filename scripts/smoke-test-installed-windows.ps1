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
  Write-Host "PASS: KAYAN-Setup.exe installed the database service, prepared the database, and started a healthy API."
} finally {
  if ($api -and -not $api.HasExited) { Stop-Process -Id $api.Id -Force -ErrorAction SilentlyContinue }
  Stop-Service -Name "KAYAN_PostgreSQL" -Force -ErrorAction SilentlyContinue
}
