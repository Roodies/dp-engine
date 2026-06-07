# ============================================================
# DownloadPilot Engine - Unified Installer / Uninstaller
# ============================================================
# Usage:
#   Install:    irm https://raw.githubusercontent.com/Roodies/dp-engine/main/install.ps1 | iex
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

# -- Constants --
$AppName     = "DownloadPilot Engine"
$InstallDir  = "$env:LOCALAPPDATA\DownloadOrganizerPro"
$ExePath     = "$InstallDir\DownloadOrganizerHelper.exe"
$HostName    = "com.downloadorganizer.folderhelper"
$ExtId       = "eianiiieigdplanmjjlchcjpebdcggal"
$DownloadUrl = "https://raw.githubusercontent.com/Roodies/dp-engine/main/payload.zip"

# -- Browser Vendor Paths (single source of truth) --
$BrowserVendors = @(
    "Google\Chrome",
    "Microsoft\Edge",
    "BraveSoftware\Brave-Browser",
    "Opera Software\Opera Stable",
    "Vivaldi"
)

# -- Shared Helpers --
function Get-NativeHostRegPaths {
    $BrowserVendors | ForEach-Object { "HKCU:\SOFTWARE\$_\NativeMessagingHosts\$HostName" }
}

function Get-ExtensionRegPaths {
    $BrowserVendors | ForEach-Object { "HKCU:\Software\$_\Extensions\$ExtId" }
}

function Set-RegistryKeyValue {
    param(
        [string]$Path,
        [string]$Value,
        [string]$PropertyName = $null
    )
    $parent = Split-Path $Path
    if (!(Test-Path $parent)) { New-Item -Path $parent -Force | Out-Null }
    if (!(Test-Path $Path))   { New-Item -Path $Path   -Force | Out-Null }
    if ($PropertyName) {
        Set-ItemProperty -Path $Path -Name $PropertyName -Value $Value -Force | Out-Null
    } else {
        Set-Item -Path $Path -Value $Value | Out-Null
    }
}

# -- Detection --
function Test-HelperInstalled {
    if (-not (Test-Path $ExePath)) { return $false }
    $regPath = "HKCU:\SOFTWARE\Google\Chrome\NativeMessagingHosts\$HostName"
    if (Test-Path $regPath) { return $true }
    if (Test-Path "$InstallDir\manifest.json") { return $true }
    return $false
}

# -- Uninstall Logic --
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
    Get-NativeHostRegPaths | ForEach-Object {
        Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 4. Remove external extension keys + uninstall entry
    Write-Host "  [4/5] Cleaning up registry entries..." -ForegroundColor Gray
    Get-ExtensionRegPaths | ForEach-Object {
        Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\DownloadPilotEngine" -Recurse -Force -ErrorAction SilentlyContinue

    # 5. Delete install directory
    Write-Host "  [5/5] Removing installed files..." -ForegroundColor Gray
    if (Test-Path $InstallDir) {
        Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "  $AppName has been uninstalled successfully." -ForegroundColor Green
    Write-Host ""
}

# -- Install Logic --
function Invoke-Install {
    Write-Host ""
    Write-Host "  ======================================================" -ForegroundColor Cyan
    Write-Host "     $AppName - Installer" -ForegroundColor Cyan
    Write-Host "  ======================================================" -ForegroundColor Cyan
    Write-Host ""

    $tempZip = Join-Path $env:TEMP "payload.zip"

    # 1. Check for local payload first (for offline/dev installs)
    $localZip = $null
    $localZipFallback = $null
    if ($PSScriptRoot) {
        $localZip = Join-Path $PSScriptRoot "payload.zip"
        $localZipFallback = Join-Path $PSScriptRoot "installer\Output\payload.zip"
    }

    if ($localZip -and (Test-Path $localZip)) {
        Write-Host "  [1/3] Using local payload: $localZip" -ForegroundColor Gray
        $tempZip = $localZip
    }
    elseif ($localZipFallback -and (Test-Path $localZipFallback)) {
        Write-Host "  [1/3] Using local payload: $localZipFallback" -ForegroundColor Gray
        $tempZip = $localZipFallback
    }
    else {
        # Download from GitHub
        Write-Host "  [1/3] Downloading payload archive..." -ForegroundColor Gray
        try {
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $tempZip -UseBasicParsing
            Write-Host "         Downloaded successfully." -ForegroundColor Green
        }
        catch {
            Write-Host ""
            Write-Host "  ERROR: Failed to download the payload archive." -ForegroundColor Red
            Write-Host "  URL: $DownloadUrl" -ForegroundColor Red
            Write-Host "  Details: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            return
        }
    }

    # 2. Extract payload directly to local appdata folder
    Write-Host "  [2/3] Installing engine files..." -ForegroundColor Gray
    try {
        if (Test-Path $InstallDir) {
            # Try to stop running instances first
            Get-Process -Name "DownloadOrganizerHelper" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 100
            Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        Expand-Archive -Path $tempZip -DestinationPath $InstallDir -Force
    }
    catch {
        Write-Host ""
        Write-Host "  ERROR: Failed to install engine files." -ForegroundColor Red
        Write-Host "  Details: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        return
    }

    # 3. Generate native messaging manifest json
    Write-Host "        Generating manifest file..." -ForegroundColor Gray
    try {
        $manifest = @{
            name = $HostName
            description = "$AppName - Native Helper"
            path = $ExePath.Replace("/", "\\")
            type = "stdio"
            allowed_origins = @(
                "chrome-extension://ddmkkklonogdgngnhpfmidconkgfkjic/",
                "chrome-extension://eianiiieigdplanmjjlchcjpebdcggal/",
                "chrome-extension://jlaoiphlphakdkbdnfbkmognkepocidc/"
            )
        }
        $manifest | ConvertTo-Json -Depth 5 | Out-File -FilePath "$InstallDir\manifest.json" -Encoding utf8 -Force
    }
    catch {
        Write-Host "  WARNING: Failed to generate native messaging manifest." -ForegroundColor Yellow
    }

    # 4. Copy uninstaller script (download if piped)
    Write-Host "        Setting up offline uninstaller..." -ForegroundColor Gray
    try {
        if ($MyInvocation.MyCommand.Path) {
            Copy-Item -Path $MyInvocation.MyCommand.Path -Destination "$InstallDir\uninstall.ps1" -Force
        } else {
            # Piped execution: fetch raw install script from repo
            $ScriptUrl = "https://raw.githubusercontent.com/Roodies/dp-engine/main/install.ps1"
            Invoke-WebRequest -Uri $ScriptUrl -OutFile "$InstallDir\uninstall.ps1" -UseBasicParsing
        }
    } catch { }

    # 5. Register native messaging host registry keys (HKCU)
    Write-Host "        Registering with browsers..." -ForegroundColor Gray
    try {
        Get-NativeHostRegPaths | ForEach-Object {
            Set-RegistryKeyValue -Path $_ -Value "$InstallDir\manifest.json"
        }
    }
    catch {
        Write-Host "  WARNING: Failed to write native messaging registry keys." -ForegroundColor Yellow
    }

    # 6. Register external browser extension registry keys (HKCU)
    Write-Host "        Registering extension integrations..." -ForegroundColor Gray
    try {
        $updateUrl = "https://clients2.google.com/service/update2/crx"
        Get-ExtensionRegPaths | ForEach-Object {
            Set-RegistryKeyValue -Path $_ -PropertyName "update_url" -Value $updateUrl
        }
    }
    catch {
        Write-Host "  WARNING: Failed to write extension integration registry keys." -ForegroundColor Yellow
    }

    # 7. Register Windows Uninstall Entry
    Write-Host "        Creating Windows Control Panel entry..." -ForegroundColor Gray
    try {
        $uninstallKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\DownloadPilotEngine"
        if (!(Test-Path $uninstallKey)) { New-Item -Path $uninstallKey -Force | Out-Null }
        Set-ItemProperty -Path $uninstallKey -Name "DisplayName" -Value $AppName -Force
        Set-ItemProperty -Path $uninstallKey -Name "DisplayVersion" -Value "1.0.0" -Force
        Set-ItemProperty -Path $uninstallKey -Name "Publisher" -Value "DownloadPilot" -Force
        Set-ItemProperty -Path $uninstallKey -Name "InstallLocation" -Value $InstallDir -Force
        Set-ItemProperty -Path $uninstallKey -Name "DisplayIcon" -Value $ExePath -Force
        Set-ItemProperty -Path $uninstallKey -Name "UninstallString" -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\uninstall.ps1`" --uninstall" -Force
        Set-ItemProperty -Path $uninstallKey -Name "QuietUninstallString" -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\uninstall.ps1`" --uninstall --silent" -Force
        Set-ItemProperty -Name "NoModify" -Value 1 -PropertyType DWord -Path $uninstallKey -Force
        Set-ItemProperty -Name "NoRepair" -Value 1 -PropertyType DWord -Path $uninstallKey -Force
    }
    catch { }

    # 8. Clean up temp download (only if we downloaded it)
    if ($tempZip -eq (Join-Path $env:TEMP "payload.zip") -and (Test-Path $tempZip)) {
        Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
    }

    # 9. Verify installation
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
        Write-Host "  Try running the installer manually." -ForegroundColor Yellow
        Write-Host ""
    }
}

# -- Main Entry Point --
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
    # Already installed - act as uninstaller
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
        Write-Host "     $AppName - Already Installed" -ForegroundColor Cyan
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
    # Not installed - install
    Invoke-Install
}
