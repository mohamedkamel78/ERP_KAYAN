<#
.SYNOPSIS
  Builds the Windows desktop copy of KAYAN ERP: one folder that starts its own
  API server, with no terminal, no Node on PATH and no commands to type.

.DESCRIPTION
  The result is a folder shaped like this:

      KAYAN-ERP\
        erp_kayan.exe                 the program
        flutter_windows.dll, data\    the client runtime
        backend\dist\src\main.js      the API server
        backend\node_modules\         its libraries, production only
        backend\prisma\               the schema and its migrations
        backend\scripts\              database preparation
        backend\node\node.exe         a Node runtime that ships with the app

  The only customer deliverable is KAYAN-Setup.exe. The assembled folder is
  an intermediate build input and is not published as a ZIP. Only the build
  machine needs Flutter, Node and Inno Setup.

  Run this from the repository root, on a Windows machine, with Flutter and
  Node installed for *building* (the end user needs neither).

.PARAMETER Output
  Where to assemble. Default: build\desktop

.PARAMETER SkipZip
  Do not create a ZIP; the only supported deliverable is the installer.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\build-desktop-windows.ps1
#>

[CmdletBinding()]
param(
  [string]$Output = "build\desktop",
  [switch]$SkipZip,
  [string]$NodeVersion = "24.21.0"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Step($number, $text) {
  Write-Host ""
  Write-Host "[$number] $text" -ForegroundColor Cyan
}

function Fail($text) {
  Write-Host ""
  Write-Host "[X] $text" -ForegroundColor Red
  exit 1
}

function Need($command, $hint) {
  if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
    Fail "$command is not on PATH. $hint"
  }
}

function Get-PeMachine([string]$path) {
  $stream = [System.IO.File]::OpenRead($path)
  $reader = [System.IO.BinaryReader]::new($stream)
  try {
    if ($reader.ReadUInt16() -ne 0x5A4D) { return $null }
    $stream.Position = 0x3c
    $stream.Position = $reader.ReadInt32()
    if ($reader.ReadUInt32() -ne 0x00004550) { return $null }
    return $reader.ReadUInt16()
  } finally {
    $reader.Dispose()
  }
}

Write-Host "============================================================"
Write-Host "  KAYAN ERP  -  building the Windows desktop program"
Write-Host "============================================================"

Need flutter "Install it from https://docs.flutter.dev/get-started/install/windows"
Need node    "Install it from https://nodejs.org (only for building, not for the user)."
Need npm     "Install Node.js from https://nodejs.org (only for building)."
if ((node -p "process.arch").Trim() -ne "x64") {
  Fail "The build-time Node.js must be x64 so native npm dependencies are built for Windows x64."
}

$stage = Join-Path $root $Output
$appFolder = Join-Path $stage "KAYAN-ERP"
$backendFolder = Join-Path $appFolder "backend"
$backendSource = Join-Path $root "backend"

# ---------------------------------------------------------------- 1. server
Step "1/8" "Building the API server"
Push-Location $backendSource
try {
  npm install --no-audit --no-fund
  if ($LASTEXITCODE -ne 0) { Fail "npm install failed in backend." }

  npx prisma generate
  if ($LASTEXITCODE -ne 0) { Fail "prisma generate failed." }

  npm run build
  if ($LASTEXITCODE -ne 0) { Fail "nest build failed." }
} finally {
  Pop-Location
}

# --------------------------------------------------------------- 2. staging
Step "2/8" "Assembling the program folder"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force -Path $backendFolder | Out-Null

# Only the pieces a running server needs. No source, no tests, no secrets.
Copy-Item (Join-Path $backendSource "dist") $backendFolder -Recurse
Copy-Item (Join-Path $backendSource "prisma") $backendFolder -Recurse
Copy-Item (Join-Path $backendSource "scripts") $backendFolder -Recurse
# The installer invokes the root-level PostgreSQL manager from the staged
# backend scripts directory; the backend source scripts do not include it.
$stagedScripts = Join-Path $backendFolder "scripts"
Copy-Item (Join-Path $root "scripts\manage-kayan-db.ps1") (Join-Path $stagedScripts "manage-kayan-db.ps1") -Force
Copy-Item (Join-Path $root "scripts\install-kayan-database.ps1") (Join-Path $stagedScripts "install-kayan-database.ps1") -Force
Copy-Item (Join-Path $backendSource "package.json") $backendFolder
Copy-Item (Join-Path $backendSource "package-lock.json") $backendFolder
Copy-Item (Join-Path $backendSource ".env.production.example") $backendFolder

# The development .env is deliberately NOT copied. The packaged program writes
# its own settings, with fresh secrets, into the machine's application-data
# folder on first run. See docs/DESKTOP_WINDOWS.md.

# Source maps belong to a debugging session on the build machine, not to a
# customer's installation: they point at source files that do not travel, and
# they make the package bigger for nothing anyone can use. The compiled server
# runs exactly the same without them.
$maps = @(Get-ChildItem (Join-Path $backendFolder "dist") -Recurse -Filter "*.map" -ErrorAction SilentlyContinue)
if ($maps.Count -gt 0) {
  $maps | Remove-Item -Force
  Write-Host "      left $($maps.Count) source map(s) out of the package"
}

# Declaration files are read by a compiler, and prisma\seed.ts is read by a
# developer's ts-node. The packaged server needs neither: what runs on a fresh
# machine is dist\prisma\seed.js, the compiled form of that same file, called
# by scripts\prepare-database.mjs.
$declarations = @(Get-ChildItem (Join-Path $backendFolder "dist") -Recurse -Filter "*.d.ts" -ErrorAction SilentlyContinue)
if ($declarations.Count -gt 0) {
  $declarations | Remove-Item -Force
  Write-Host "      left $($declarations.Count) declaration file(s) out of the package"
}
$seedSource = Join-Path $backendFolder "prisma\seed.ts"
if (Test-Path $seedSource) {
  Remove-Item -Force $seedSource
  Write-Host "      left the server's TypeScript source out of the package"
}

# The KAYAN icon travels with the program: the same app_icon.ico the exe was
# built from (the installer points the shortcuts at this copy), and Kayan.png
# itself — the one source every icon was rendered from.
$iconsFolder = Join-Path $appFolder "icons"
New-Item -ItemType Directory -Force -Path $iconsFolder | Out-Null
Copy-Item (Join-Path $root "windows\runner\resources\app_icon.ico") $iconsFolder -Force
Copy-Item (Join-Path $root "Kayan.png") $iconsFolder -Force
Write-Host "      KAYAN icon files copied into the package (icons\)"

# ------------------------------------------------- 3. production libraries
Step "3/8" "Installing the server's libraries (production only)"
Push-Location $backendFolder
try {
  npm ci --omit=dev --no-audit --no-fund
  if ($LASTEXITCODE -ne 0) { Fail "npm ci failed while assembling the server." }

  # Prisma needs its query engine for Windows next to the generated client.
  npx prisma generate
  if ($LASTEXITCODE -ne 0) { Fail "prisma generate failed in the staged server." }
} finally {
  Pop-Location
}

# --------------------------------------------------------- 4. Node runtime
Step "4/8" "Adding the Node runtime the program ships with"
$toolsFolder = Join-Path $env:LOCALAPPDATA "kayan-tools"
$portableNode = Join-Path $toolsFolder "node\node.exe"
$zipUrl = "https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-win-x64.zip"

if ((Test-Path $portableNode) -and (Get-PeMachine $portableNode) -ne 0x8664) {
  Write-Host "      cached node.exe is not x64; replacing it"
  Remove-Item -Recurse -Force (Split-Path -Parent $portableNode)
}

if (-not (Test-Path $portableNode)) {
  Write-Host "      downloading Node $NodeVersion (about 36 MB)"
  $zipFile = Join-Path $env:TEMP "kayan-node-$NodeVersion.zip"
  if (Test-Path $zipFile) { Remove-Item -Force $zipFile }
  try {
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing
  } catch {
    Fail "Could not download Node from $zipUrl . Download it in a browser, save it as $zipFile, and run this script again."
  }
  New-Item -ItemType Directory -Force -Path $toolsFolder | Out-Null
  Expand-Archive -Path $zipFile -DestinationPath $toolsFolder -Force
  $extracted = Join-Path $toolsFolder "node-v$NodeVersion-win-x64"
  if (Test-Path (Join-Path $extracted "node.exe")) {
    New-Item -ItemType Directory -Force -Path (Join-Path $toolsFolder "node") | Out-Null
    Copy-Item (Join-Path $extracted "*") (Join-Path $toolsFolder "node") -Recurse -Force
  }
  if (-not (Test-Path $portableNode)) { Fail "Node was downloaded but node.exe was not found." }
}
if ((Get-PeMachine $portableNode) -ne 0x8664) {
  Fail "The bundled node.exe is not a Windows x64 (AMD64) binary."
}

$runtimeFolder = Join-Path $backendFolder "node"
New-Item -ItemType Directory -Force -Path $runtimeFolder | Out-Null
Copy-Item $portableNode $runtimeFolder -Force
# node.exe needs nothing else to run a script, but the licence travels with it.
$license = Join-Path (Split-Path -Parent $portableNode) "LICENSE"
if (Test-Path $license) { Copy-Item $license $runtimeFolder -Force }
Write-Host "      node.exe copied into the program folder"

# --------------------------------------------------- 5. PostgreSQL tools
Step "5/8" "Bundling the PostgreSQL backup tools (pg_dump / pg_restore)"
# The backup screen needs pg_dump and pg_restore. They travel inside the
# program folder (backend\pg) so the machine that runs it does not have to
# guess an installation, and so the tools match a PostgreSQL this project
# supports. The copy is made from, in order of preference:
#   1. the portable PostgreSQL that scripts\install-postgres-portable.bat
#      provisions (the same one the program's own database runs on);
#   2. a PostgreSQL installed on this build machine, newest first;
#   3. failing both, this script provisions the same portable toolchain the
#      installer script uses - the same download, the same folder - so a
#      fresh build machine (including CI) can always produce a package.
# Only the two programs and the DLLs they need are copied. Nothing is
# installed as a Windows service, nothing existing is replaced, and no
# PostgreSQL setting is read or changed. PostgreSQL's licence allows
# distributing these binaries with an application.
$pgBin = $null
$toolsFolder = Join-Path $env:LOCALAPPDATA "kayan-tools"
$portablePg = Join-Path $toolsFolder "pgsql\bin"
# Always use a clean extraction of the official EDB archive. Reusing
# %LOCALAPPDATA%\\kayan-tools\\pgsql is unsafe: an older developer helper or
# an unrelated PostgreSQL build can leave binaries compiled against an absolute
# build-machine timezone path. That makes the installed database fail at startup.
$pgVersion = "16.15"
$archiveUrl = "https://get.enterprisedb.com/postgresql/postgresql-$pgVersion-1-windows-x64-binaries.zip"
$archiveFile = Join-Path $env:TEMP "kayan-postgresql-$pgVersion-binaries.zip"
$extractRoot = Join-Path $env:TEMP "kayan-postgresql-runtime-$pgVersion"
Write-Host "      downloading the official EDB PostgreSQL $pgVersion binary archive"
if ((Test-Path $archiveFile) -and ((Get-Item $archiveFile).Length -lt 20000000)) { Remove-Item -Force $archiveFile }
if (-not (Test-Path $archiveFile)) {
  & curl.exe -fsSL --connect-timeout 20 --max-time 240 --retry 3 --retry-delay 2 --retry-all-errors -o $archiveFile $archiveUrl
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $archiveFile)) { Fail ("Could not download the official EDB PostgreSQL binary archive from " + $archiveUrl) }
}
if ((Get-Item $archiveFile).Length -lt 20000000) { Fail "The PostgreSQL binary archive is incomplete or unexpectedly small." }
$archiveHeader = [System.IO.File]::ReadAllBytes($archiveFile)[0..3]
if ($archiveHeader[0] -ne 0x50 -or $archiveHeader[1] -ne 0x4B) { Fail "The PostgreSQL archive is not a ZIP file; refusing to package it." }
if (Test-Path $extractRoot) { Remove-Item -Recurse -Force $extractRoot }
New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
Expand-Archive -Path $archiveFile -DestinationPath $extractRoot -Force
$initDbCandidate = Get-ChildItem -Path $extractRoot -Filter "initdb.exe" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $initDbCandidate) {
  $layout = (Get-ChildItem -Path $extractRoot -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -First 60 -ExpandProperty FullName) -join [Environment]::NewLine
  Fail ("The official EDB archive extracted but contains no initdb.exe. Extracted files:" + [Environment]::NewLine + $layout)
}
$pgBin = $initDbCandidate.Directory.FullName
if (-not (Test-Path (Join-Path $pgBin "pg_dump.exe")) -or -not (Test-Path (Join-Path $pgBin "postgres.exe"))) { Fail "EDB archive is missing required PostgreSQL tools." }
if ((Get-PeMachine (Join-Path $pgBin "initdb.exe")) -ne 0x8664) { Fail "The downloaded PostgreSQL initdb is not a Windows x64 executable." }
Write-Host ("      official EDB PostgreSQL binaries extracted from " + $pgBin)
$pgFolder = Join-Path $backendFolder "pg"
$pgRoot = Split-Path -Parent $pgBin
$pgBinFolder = Join-Path $pgFolder "bin"
New-Item -ItemType Directory -Force -Path $pgBinFolder | Out-Null
foreach ($tool in @("pg_dump.exe", "pg_restore.exe", "psql.exe", "initdb.exe", "pg_ctl.exe", "postgres.exe")) {
  $src = Join-Path $pgBin $tool
  if (Test-Path $src) {
    Copy-Item $src $pgBinFolder -Force
  }
}
# Keep PostgreSQL's expected bin/ and share/ sibling layout. Its relocatable
# path logic uses the executable's location to find timezone and catalog data.
Get-ChildItem $pgBin -Filter "*.dll" | Copy-Item -Destination $pgBinFolder -Force
$pgRoot = Split-Path -Parent $pgBin
$shareSource = Join-Path $pgRoot "share"
if (-not (Test-Path (Join-Path $shareSource "postgres.bki"))) {
  $shareSource = Join-Path $pgBin "share"
}
if (-not (Test-Path (Join-Path $shareSource "postgres.bki"))) {
  Fail "The PostgreSQL installer did not provide the required share/postgres.bki data."
}
Copy-Item $shareSource (Join-Path $pgFolder "share") -Recurse -Force
$libSource = Join-Path $pgRoot "lib"
if (-not (Test-Path (Join-Path $libSource "plpgsql.dll"))) {
  Fail "The EDB archive is missing the required PostgreSQL lib/plpgsql.dll runtime."
}
Copy-Item $libSource (Join-Path $pgFolder "lib") -Recurse -Force
Write-Host "      PostgreSQL runtime lib/ directory bundled"
Copy-Item (Join-Path $root "scripts\manage-kayan-db.ps1") (Join-Path $backendFolder "scripts\manage-kayan-db.ps1") -Force
Copy-Item (Join-Path $root "scripts\install-kayan-database.ps1") (Join-Path $backendFolder "scripts\install-kayan-database.ps1") -Force

# Probe the exact packaged bin/share layout before producing an installer.
$probeData = Join-Path $env:TEMP ("kayan-pg-initdb-probe-" + [guid]::NewGuid().ToString("N"))
$probeShare = Join-Path $pgFolder "share"
try {
  & (Join-Path $pgBinFolder "initdb.exe") -D $probeData -U postgres -A trust -E UTF8 --locale=C -L $probeShare
  if ($LASTEXITCODE -ne 0) {
    Fail "The bundled PostgreSQL initdb could not initialize with the packaged bin/share layout. Do not ship this package."
  }
} finally {
  if (Test-Path $probeData) { Remove-Item $probeData -Recurse -Force -ErrorAction SilentlyContinue }
}
foreach ($tool in @("pg_dump.exe", "pg_restore.exe")) {
  $probe = Join-Path $pgBinFolder $tool
  $line = & $probe --version 2>&1
  if ($LASTEXITCODE -ne 0 -or -not ("$line" -match [regex]::Escape($tool.Replace(".exe", "")))) {
    Fail "The bundled $tool did not answer --version from $pgBinFolder. The package is not shippable."
  }
  Write-Host "      bundled $($line | Select-Object -First 1)"
}

# ------------------------------------------------------------- 6. client
Step "6/8" "Building the client (Flutter, Windows, release)"
# erp_kayan.exe takes its icon (window and taskbar too) from the Windows
# resource compiled into it: windows\runner\resources\app_icon.ico, which
# tools\generate_icons.py renders from Kayan.png at the repository root. The
# build stops early if that file is missing, rather than shipping a program
# with a blank icon.
$windowIcon = Join-Path $root "windows\runner\resources\app_icon.ico"
if (-not (Test-Path $windowIcon)) {
  Fail ("windows\runner\resources\app_icon.ico is missing, so the program would " +
        "build without the KAYAN icon. Restore it (python tools\generate_icons.py " +
        "regenerates it from Kayan.png) and run this script again.")
}
flutter build windows --release --dart-define=APP_ENV=production
if ($LASTEXITCODE -ne 0) { Fail "flutter build windows failed." }

$release = Join-Path $root "build\windows\x64\runner\Release"
if (-not (Test-Path (Join-Path $release "erp_kayan.exe"))) {
  Fail "The client build finished but erp_kayan.exe is not in $release ."
}
Copy-Item (Join-Path $release "*") $appFolder -Recurse -Force

Write-Host "      building Flutter Web client for browser and LAN access..."
flutter build web --release --dart-define=APP_ENV=production
if ($LASTEXITCODE -eq 0) {
  $webSource = Join-Path $root "build\web"
  $webDest = Join-Path $backendFolder "web"
  if (Test-Path $webSource) {
    New-Item -ItemType Directory -Force -Path $webDest | Out-Null
    Copy-Item (Join-Path $webSource "*") $webDest -Recurse -Force
    Write-Host "      bundled Flutter Web client into backend\web"
  }
} else {
  Write-Host "      warning: flutter build web failed; desktop client still operational"
}

# Reject any x86, ARM64, malformed, or non-PE Windows native binary before
# creating distributable artifacts.
$nativeFiles = Get-ChildItem -Path $appFolder -Recurse -File |
  Where-Object { $_.Extension -in @(".exe", ".dll", ".node") }
$windowsNativeCount = 0
foreach ($file in $nativeFiles) {
  $machine = Get-PeMachine $file.FullName
  if ($null -eq $machine) {
    if ($file.Extension -eq ".node") { continue }
    Fail "Expected a Windows PE binary but found an invalid file: $($file.FullName)"
  }
  if ($machine -ne 0x8664) {
    Fail "Native dependency is not Windows x64 (AMD64): $($file.FullName)"
  }
  $windowsNativeCount++
}
Write-Host "      verified $windowsNativeCount Windows native binaries: all x64 (AMD64)"

# ------------------------------------------------------------- 6. notes
Step "7/8" "Writing the note that travels with the program"
$note = @"
KAYAN ERP - Windows installer
=============================

Install KAYAN-Setup.exe. The installer provisions the dedicated local
PostgreSQL service and configures the application automatically.

Runtime database settings:
    %ProgramData%\KAYAN-ERP\kayan.env
This file is protected by Windows ACL for the installing user, SYSTEM and
local Administrators. Do not share it.

Application logs and JSON company backups:
    %APPDATA%\KAYAN-ERP\

The installer uses port 5433 for the local KAYAN_PostgreSQL service and port
3000 for the application API. The Windows Firewall rule is limited to private
and domain networks.

No separate Node.js, Flutter, Git, npm or PostgreSQL installation is needed.
Uninstalling KAYAN ERP preserves the PostgreSQL service, its runtime, company database, and protected settings under %ProgramData%\KAYAN-ERP.

If the server does not start, read:
    %APPDATA%\KAYAN-ERP\logs\backend.log
"@
Set-Content -Path (Join-Path $appFolder "README.txt") -Value $note -Encoding UTF8

# The assembled folder is an intermediate input only. Never create a ZIP.

# ------------------------------------------------------- 7. installer (required)
Step "8/8" "Making the installer a customer can run"
$installer = $null
$iscc = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
if (-not $iscc) {
  # ${env:ProgramFiles(x86)} needs the braces: without them PowerShell expands
  # $env:ProgramFiles and leaves "(x86)" as literal text, which builds a path
  # that never exists - and the installer would silently never be made.
  foreach ($probe in @(
      "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
      "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
      "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe")) {
    if ($probe -and (Test-Path $probe)) { $iscc = @{ Source = $probe }; break }
  }
}
if ($iscc) {
  & $iscc.Source "/DSourceDir=$appFolder" "/DOutputDir=$stage" `
                 (Join-Path $root "scripts\installer-windows.iss")
  if ($LASTEXITCODE -ne 0) { Fail "Inno Setup ran but did not produce the installer." }
  $installer = Join-Path $stage "KAYAN-Setup.exe"
  if (-not (Test-Path $installer)) { Fail "Inno Setup completed but KAYAN-Setup.exe was not created." }
  Write-Host "      installer written: $installer"
} else {
  Fail "Inno Setup 6 is required to create the only supported deliverable, KAYAN-Setup.exe."
}

$size = (Get-ChildItem $appFolder -Recurse -Force | Measure-Object -Property Length -Sum).Sum
Write-Host ""
Write-Host "============================================================"
Write-Host "  DONE" -ForegroundColor Green
Write-Host "============================================================"
Write-Host ""
Write-Host "  Program folder : $appFolder"
Write-Host "  Total size     : $([math]::Round($size / 1MB, 1)) MB"
if ($installer) {
  Write-Host "  Installer      : $installer   <- the file a customer runs" -ForegroundColor Green
}
Write-Host ""
Write-Host "  Try it now:"
Write-Host "      $appFolder\erp_kayan.exe"
Write-Host ""
Write-Host ""

Write-Host "  Deliver only KAYAN-Setup.exe. Do not distribute the intermediate folder."