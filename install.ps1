# ============================================================
# Lunor Download Engine — Unified Installer / Uninstaller
# ============================================================
# Usage:
#   Install:    irm https://raw.githubusercontent.com/Roodies/lunor-engine/main/install.ps1 | iex
#   Uninstall:  Run the same command again when already installed
#
# Flags (when running locally):
#   .\install.ps1                 # Interactive install or uninstall
#   .\install.ps1 --silent        # Silent install (no prompts)
#   .\install.ps1 --uninstall     # Force uninstall without prompting
# ============================================================

param(
    [switch]$silent,
    [switch]$uninstall
)

# Also support double-dash string args when piped via irm | iex
if ($args -contains '--silent')    { $silent    = $true }
if ($args -contains '--uninstall') { $uninstall = $true }

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ── Constants ──
$AppName     = "Lunor Download Engine"
$InstallDir  = "$env:LOCALAPPDATA\DownloadOrganizerPro"
$ExePath     = "$InstallDir\DownloadOrganizerHelper.exe"
$HostName    = "com.downloadorganizer.folderhelper"
$ExtId       = "eianiiieigdplanmjjlchcjpebdcggal"
$DownloadUrl = "https://github.com/Roodies/lunor-engine/releases/latest/download/LunorEngineSetup.exe"

# ── Detection ──
function Test-HelperInstalled {
    if (-not (Test-Path $ExePath)) { return $false }
    $regPath = "HKCU:\SOFTWARE\Google\Chrome\NativeMessagingHosts\$HostName"
    if (Test-Path $regPath) { return $true }
    if (Test-Path "$InstallDir\manifest.json") { return $true }
    return $false
}

# ── Uninstall Logic ──
function Invoke-Uninstall {
    Write-Host ""
    Write-Host "  Uninstalling $AppName..." -ForegroundColor Cyan
    Write-Host ""

    # 1. Revert folder changes via helper's built-in uninstaller
    if (Test-Path $ExePath) {
        Write-Host "  [1/5] Reverting folder customizations..." -ForegroundColor Gray
        try {
            Start-Process -FilePath $ExePath -ArgumentList "--uninstall", "--silent" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        } catch { }
    }

    # 2. Kill running helper processes
    Write-Host "  [2/5] Stopping helper processes..." -ForegroundColor Gray
    Get-Process -Name "DownloadOrganizerHelper" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    # 3. Remove NativeMessagingHosts registry keys (HKCU)
    Write-Host "  [3/5] Removing browser registrations..." -ForegroundColor Gray
    @(
        "SOFTWARE\Google\Chrome\NativeMessagingHosts\$HostName",
        "SOFTWARE\Microsoft\Edge\NativeMessagingHosts\$HostName",
        "SOFTWARE\BraveSoftware\Brave-Browser\NativeMessagingHosts\$HostName",
        "SOFTWARE\Opera Software\Opera Stable\NativeMessagingHosts\$HostName",
        "SOFTWARE\Vivaldi\NativeMessagingHosts\$HostName"
    ) | ForEach-Object {
        Remove-Item "HKCU:\$_" -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 4. Remove external extension keys + uninstall entry
    Write-Host "  [4/5] Cleaning up registry entries..." -ForegroundColor Gray
    @(
        "Software\Google\Chrome\Extensions\$ExtId",
        "Software\Microsoft\Edge\Extensions\$ExtId",
        "Software\BraveSoftware\Brave-Browser\Extensions\$ExtId",
        "Software\Opera Software\Opera Stable\Extensions\$ExtId",
        "Software\Vivaldi\Extensions\$ExtId"
    ) | ForEach-Object {
        Remove-Item "HKCU:\$_" -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\LunorDownloadEngine" -Recurse -Force -ErrorAction SilentlyContinue

    # 5. Delete install directory
    Write-Host "  [5/5] Removing installed files..." -ForegroundColor Gray
    if (Test-Path $InstallDir) {
        Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "  $AppName has been uninstalled successfully." -ForegroundColor Green
    Write-Host ""
}

# ── Install Logic ──
function Invoke-Install {
    Write-Host ""
    Write-Host "  ======================================================" -ForegroundColor Cyan
    Write-Host "     $AppName — Installer" -ForegroundColor Cyan
    Write-Host "  ======================================================" -ForegroundColor Cyan
    Write-Host ""

    $tempExe = Join-Path $env:TEMP "LunorEngineSetup.exe"

    # 1. Check for local copy first (for offline/dev installs)
    $localExe = Join-Path $PSScriptRoot "LunorEngineSetup.exe"
    $localExeFallback = Join-Path $PSScriptRoot "installer\Output\LunorEngineSetup.exe"

    if ($PSScriptRoot -and (Test-Path $localExe)) {
        Write-Host "  [1/3] Using local installer: $localExe" -ForegroundColor Gray
        $tempExe = $localExe
    }
    elseif ($PSScriptRoot -and (Test-Path $localExeFallback)) {
        Write-Host "  [1/3] Using local installer: $localExeFallback" -ForegroundColor Gray
        $tempExe = $localExeFallback
    }
    else {
        # Download from GitHub
        Write-Host "  [1/3] Downloading installer..." -ForegroundColor Gray
        try {
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $tempExe -UseBasicParsing
            Write-Host "         Downloaded successfully." -ForegroundColor Green
        }
        catch {
            Write-Host ""
            Write-Host "  ERROR: Failed to download the installer." -ForegroundColor Red
            Write-Host "  URL: $DownloadUrl" -ForegroundColor Red
            Write-Host "  Details: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Please check your internet connection and try again." -ForegroundColor Yellow
            Write-Host "  Or download manually from:" -ForegroundColor Yellow
            Write-Host "  $DownloadUrl" -ForegroundColor Yellow
            Write-Host ""
            return
        }
    }

    # 2. Run the installer silently
    Write-Host "  [2/3] Installing engine..." -ForegroundColor Gray
    try {
        Start-Process -FilePath $tempExe -ArgumentList "--silent" -Wait -NoNewWindow
    }
    catch {
        Write-Host ""
        Write-Host "  ERROR: Failed to run the installer." -ForegroundColor Red
        Write-Host "  Details: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        return
    }

    # 3. Clean up temp download (only if we downloaded it)
    if ($tempExe -eq (Join-Path $env:TEMP "LunorEngineSetup.exe") -and (Test-Path $tempExe)) {
        Remove-Item $tempExe -Force -ErrorAction SilentlyContinue
    }

    # 4. Verify installation
    Write-Host "  [3/3] Verifying installation..." -ForegroundColor Gray
    Start-Sleep -Milliseconds 500
    if (Test-HelperInstalled) {
        Write-Host ""
        Write-Host "  ======================================================" -ForegroundColor Green
        Write-Host "     $AppName installed successfully!" -ForegroundColor Green
        Write-Host "  ======================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Close ALL browser windows and reopen your browser." -ForegroundColor White
        Write-Host "  The extension will auto-connect to the helper." -ForegroundColor White
        Write-Host ""
    }
    else {
        Write-Host ""
        Write-Host "  WARNING: Installation may not have completed properly." -ForegroundColor Yellow
        Write-Host "  Try running the installer manually:" -ForegroundColor Yellow
        Write-Host "  $DownloadUrl" -ForegroundColor Yellow
        Write-Host ""
    }
}

# ── Main Entry Point ──
$isInstalled = Test-HelperInstalled

if ($uninstall) {
    # Force uninstall mode
    if ($isInstalled) {
        Invoke-Uninstall
    }
    else {
        Write-Host ""
        Write-Host "  $AppName is not installed. Nothing to uninstall." -ForegroundColor Yellow
        Write-Host ""
    }
}
elseif ($isInstalled) {
    # Already installed — act as uninstaller
    if ($silent) {
        # Silent mode: just inform, don't uninstall without explicit --uninstall flag
        Write-Host ""
        Write-Host "  $AppName is already installed." -ForegroundColor Green
        Write-Host "  To uninstall, run with --uninstall flag." -ForegroundColor Gray
        Write-Host ""
    }
    else {
        Write-Host ""
        Write-Host "  ======================================================" -ForegroundColor Cyan
        Write-Host "     $AppName — Already Installed" -ForegroundColor Cyan
        Write-Host "  ======================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  The helper is already installed at:" -ForegroundColor White
        Write-Host "  $InstallDir" -ForegroundColor Gray
        Write-Host ""
        $choice = Read-Host "  Would you like to uninstall it? (Y/N)"
        if ($choice -match '^[Yy]') {
            Invoke-Uninstall
        }
        else {
            Write-Host ""
            Write-Host "  No changes made. Helper remains installed." -ForegroundColor Green
            Write-Host ""
        }
    }
}
else {
    # Not installed — install
    Invoke-Install
}