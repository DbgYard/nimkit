# nimkit installer for Windows (PowerShell)
# Usage:
#   irm https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/install.ps1 | iex
#   irm https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/install.ps1 | iex; Install-Nimkit -FromSource
#   powershell -ExecutionPolicy Bypass -File scripts/install.ps1 -Tag nightly -FromSource

param(
  [string]$Tag = "nightly",
  [string]$Prefix = "",
  [switch]$FromSource,
  [switch]$Force,
  [switch]$Help
)

$Repo = "DbgYard/nimkit"
if ($Prefix -eq "") { $Prefix = Join-Path $env:USERPROFILE ".nimkit\bin" }

function Write-Info($msg) { Write-Host "[nimkit] $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "[nimkit] WARN: $msg" -ForegroundColor Yellow }
function Die($msg) { Write-Host "[nimkit] ERROR: $msg" -ForegroundColor Red; exit 1 }

if ($Help) {
  Write-Host @"
nimkit installer (Windows)

Usage: install.ps1 [-Tag <tag>] [-Prefix <dir>] [-FromSource] [-Force] [-Help]

Options:
  -Tag <tag>     Release tag to download (default: nightly)
  -Prefix <dir>  Install directory (default: %USERPROFILE%\.nimkit\bin)
  -FromSource    Build from source instead of downloading binary
  -Force         Force overwrite existing installation (default: always overwrites)
  -Help          Show this help

Examples:
  install.ps1                          # install nightly, overwrite if exists
  install.ps1 -Tag v0.2.0              # update/downgrade to v0.2.0
  install.ps1 -FromSource              # rebuild from source and overwrite
"@
  exit 0
}

# Ensure install dir exists
if (-not (Test-Path $Prefix)) {
  New-Item -ItemType Directory -Path $Prefix -Force | Out-Null
}

$BinaryPath = Join-Path $Prefix "nimkit.exe"
$Asset = "nimkit-windows-amd64.exe"
$Url = "https://github.com/$Repo/releases/download/$Tag/$Asset"

function Add-ToPath {
  param([string]$Dir)
  $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if ($currentPath -split ";" -notcontains $Dir) {
    $newPath = if ($currentPath) { "$currentPath;$Dir" } else { $Dir }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "[nimkit] Added $Dir to user PATH" -ForegroundColor Green
    # also update current session
    if ($env:Path -split ";" -notcontains $Dir) {
      $env:Path += ";$Dir"
    }
  } else {
    Write-Host "[nimkit] $Dir already in PATH"
  }
}

function Try-Download {
  if (Test-Path $BinaryPath) {
    Write-Info "Existing binary at $BinaryPath — will overwrite with $Tag"
    Remove-Item -Force $BinaryPath -ErrorAction SilentlyContinue
  }
  Write-Info "Downloading $Asset from $Tag..."
  try {
    # Use TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Url -OutFile $BinaryPath -UseBasicParsing -ErrorAction Stop | Out-Null
    if (Test-Path $BinaryPath) { return $true }
  } catch {
    Write-Warn "Download failed: $($_.Exception.Message)"
    return $false
  }
  return $false
}

function Build-FromSource {
  Write-Info "Building from source..."
  $nim = Get-Command nim -ErrorAction SilentlyContinue
  if (-not $nim) { Die "Nim not found. Install Nim >= 2.0.0 via choosenim: https://github.com/dom96/choosenim" }
  $git = Get-Command git -ErrorAction SilentlyContinue
  if (-not $git) { Die "git not found. Install git first." }

  if (Test-Path $BinaryPath) {
    Write-Info "Existing binary at $BinaryPath — will overwrite with fresh build from $Tag"
    Remove-Item -Force $BinaryPath -ErrorAction SilentlyContinue
  }

  $tmp = Join-Path $env:TEMP ("nimkit-" + [Guid]::NewGuid().ToString("N"))
  if ($Tag -ne "nightly") {
    Write-Info "Cloning $Repo (tag $Tag) into $tmp..."
    git clone --depth 1 --branch $Tag "https://github.com/$Repo.git" $tmp 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
      Write-Warn "Tag $Tag not found, cloning default branch and building HEAD"
      Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
      git clone --depth 1 "https://github.com/$Repo.git" $tmp 2>&1 | Out-Null
      if ($LASTEXITCODE -ne 0) { Die "git clone failed" }
    }
  } else {
    Write-Info "Cloning $Repo into $tmp..."
    git clone --depth 1 "https://github.com/$Repo.git" $tmp 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "git clone failed" }
  }
  try {
    Push-Location $tmp
    if ($Tag -ne "nightly") {
      git fetch --depth 1 origin "refs/tags/$Tag`:refs/tags/$Tag" 2>&1 | Out-Null
      git checkout $Tag 2>&1 | Out-Null
    }
    & nim c --path:src -o:nimkit.exe src/nimkit.nim
    if ($LASTEXITCODE -ne 0) { Die "nim build failed" }
    Copy-Item -Force "$tmp\nimkit.exe" $BinaryPath
  } finally {
    Pop-Location
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }
}

# Main
if (Test-Path $BinaryPath) {
  try { $old = & $BinaryPath help 2>&1 | Select-Object -First 1; Write-Info ("Existing installation: $old - updating to $Tag...") } catch { Write-Info ("Existing installation at $BinaryPath - updating to $Tag...") }
} else {
  Write-Info "Installing nimkit ($Tag) to $Prefix"
}

if ($FromSource) {
  Build-FromSource
} else {
  if (-not (Try-Download)) {
    Write-Warn "Falling back to source build"
    Build-FromSource
  }
}

if (Test-Path $BinaryPath) {
  Add-ToPath -Dir $Prefix
  Write-Info "Installed: $BinaryPath"
  try { & $BinaryPath help 2>&1 | Select-Object -First 5 | Write-Host } catch {}
  Write-Host ""
  Write-Host "[nimkit] Restart your terminal or run: `$env:Path += `";$Prefix`"" -ForegroundColor Cyan
  Write-Host "[nimkit] Then run: nimkit help" -ForegroundColor Cyan
} else {
  Die "Install failed: $BinaryPath not found"
}
