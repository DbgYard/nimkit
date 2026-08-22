# nimkit uninstaller for Windows (PowerShell)
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/uninstall.ps1
#   irm https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/uninstall.ps1 | iex

param(
  [string]$Prefix = "",
  [switch]$Help
)

if ($Prefix -eq "") { $Prefix = Join-Path $env:USERPROFILE ".nimkit\bin" }

function Write-Info($msg) { Write-Host "[nimkit] $msg" -ForegroundColor Cyan }

if ($Help) {
  Write-Host @"
nimkit uninstaller (Windows)

Usage: uninstall.ps1 [-Prefix <dir>] [-Help]

Options:
  -Prefix <dir>  Install directory (default: %USERPROFILE%\.nimkit\bin)
  -Help          Show this help
"@
  exit 0
}

Write-Info "Uninstalling nimkit from $Prefix"

$BinaryPath = Join-Path $Prefix "nimkit.exe"
if (Test-Path $BinaryPath) {
  Remove-Item -Force $BinaryPath -ErrorAction SilentlyContinue
  Write-Host "  Removed $BinaryPath"
} else {
  Write-Host "  Binary not found at $BinaryPath (already removed?)"
}

# Remove empty dirs
if (Test-Path $Prefix) {
  # try to remove bin dir if empty
  $items = Get-ChildItem -Force $Prefix -ErrorAction SilentlyContinue
  if (-not $items -or $items.Count -eq 0) {
    Remove-Item -Force $Prefix -ErrorAction SilentlyContinue
    Write-Host "  Removed empty $Prefix"
    $parent = Split-Path $Prefix -Parent
    if ((Split-Path $parent -Leaf) -eq ".nimkit" -and (Test-Path $parent)) {
      $pitems = Get-ChildItem -Force $parent -ErrorAction SilentlyContinue
      if (-not $pitems -or $pitems.Count -eq 0) {
        Remove-Item -Force $parent -ErrorAction SilentlyContinue
        Write-Host "  Removed empty $parent"
      }
    }
  }
}

# Remove from user PATH
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -and $currentPath.Split(";") -contains $Prefix) {
  $newPath = ($currentPath.Split(";") | Where-Object { $_ -ne $Prefix -and $_ -ne "" }) -join ";"
  [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
  Write-Host "  Removed $Prefix from user PATH" -ForegroundColor Green
  # update current session
  $env:Path = ($env:Path.Split(";") | Where-Object { $_ -ne $Prefix -and $_ -ne "" }) -join ";"
} else {
  Write-Host "  $Prefix not in user PATH"
}

Write-Info "Uninstalled. Restart your terminal to refresh PATH."
