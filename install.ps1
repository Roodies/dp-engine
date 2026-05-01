# Lunor Download Manager - Native Engine Installer
# Run: Right-click Start button → Terminal (Admin) → Paste this command:
# irm https://raw.githubusercontent.com/dextabdb/lunor-engine/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

# Configuration
$AppName = "Lunor Engine"
$HostName = "com.lunor.engine"
$InstallDir = "$env:LOCALAPPDATA\LunorEngine"
$ExeName = "DownloadOrganizerHelper.exe"
$RepoUrl = "https://github.com/dextabdb/lunor-engine/releases/latest/download"

# Styling
$C1 = "Cyan"
$C2 = "Yellow"
$C3 = "Green"
$C4 = "Red"

Clear-Host
Write-Host "  _      _    _  _   _   ____  _____  " -ForegroundColor $C1
Write-Host " | |    | |  | || \ | | / __ \|  __ \ " -ForegroundColor $C1
Write-Host " | |    | |  | ||  \| || |  | | |__) |" -ForegroundColor $C1
Write-Host " | |    | |  | || . ` | ||  | |  _  / " -ForegroundColor $C1
Write-Host " | |____| |__| || |\  || |__| | | \ \ " -ForegroundColor $C1
Write-Host " |______|\____/ |_| \_| \____/|_|  \_\" -ForegroundColor $C1
Write-Host " --------------------------------------" -ForegroundColor $C1
Write-Host "      NATIVE ENGINE INSTALLER v1.0     " -ForegroundColor $C1
Write-Host ""

# Create install directory
Write-Host "📁 Preparing installation folder..." -ForegroundColor $C2
if (!(Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
}

# Download engine
$exePath = "$InstallDir\$ExeName"
$downloadUrl = "$RepoUrl/$ExeName"

Write-Host "⬇️  Downloading core engine..." -ForegroundColor $C2
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $exePath -UseBasicParsing -TimeoutSec 30
    Write-Host "✅ Engine downloaded successfully!" -ForegroundColor $C3
} catch {
    Write-Host "❌ Failed to download engine: $_" -ForegroundColor $C4
    Write-Host "   Check your internet connection or if the release exists." -ForegroundColor $C2
    Read-Host "Press Enter to exit"
    exit 1
}

# Download assets (Icons)
$icons = @(
    "icon_audio.ico", "icon_code.ico", "icon_compressed.ico", "icon_doc.ico",
    "icon_exe.ico", "icon_folder.ico", "icon_image.ico", "icon_pdf.ico",
    "icon_presentation.ico", "icon_spreadsheet.ico", "icon_video.ico"
)

Write-Host "⬇️  Fetching visual assets..." -ForegroundColor $C2
foreach ($icon in $icons) {
    try {
        Invoke-WebRequest -Uri "$RepoUrl/$icon" -OutFile "$InstallDir\$icon" -UseBasicParsing -ErrorAction SilentlyContinue
    } catch { }
}

# Create manifest.json
Write-Host "📄 Generating browser manifest..." -ForegroundColor $C2
$manifestPath = "$InstallDir\manifest.json"
$manifest = @{
    name = $HostName
    description = "Lunor Download Manager - Native Helper"
    path = $exePath
    type = "stdio"
    allowed_origins = @(
        "chrome-extension://inmcohhgccejkidlofimedccjkllpejn/",
        "chrome-extension://eianiiieigdplanmjjlchcjpebdcggal/",
        "chrome-extension://*" # Allows local testing
    )
} | ConvertTo-Json

$manifest | Out-File -FilePath $manifestPath -Encoding UTF8 -Force

# Registry for all major browsers
$registryPaths = @(
    "SOFTWARE\Google\Chrome\NativeMessagingHosts\$HostName",
    "SOFTWARE\Microsoft\Edge\NativeMessagingHosts\$HostName",
    "SOFTWARE\BraveSoftware\Brave-Browser\NativeMessagingHosts\$HostName",
    "SOFTWARE\Vivaldi\NativeMessagingHosts\$HostName",
    "SOFTWARE\Opera Software\Opera Stable\NativeMessagingHosts\$HostName"
)

Write-Host "🔧 Linking with browsers..." -ForegroundColor $C2
$count = 0
foreach ($path in $registryPaths) {
    try {
        if (!(Test-Path "HKCU:\$path")) {
            New-Item -Path "HKCU:\$path" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKCU:\$path" -Name "(Default)" -Value $manifestPath
        $count++
    } catch { }
}

Write-Host "✅ Linked with $count browser(s)!" -ForegroundColor $C3

# Verification
Write-Host "🧪 Verifying engine..." -ForegroundColor $C2
if (Test-Path $exePath) {
    $test = Start-Process -FilePath $exePath -ArgumentList "--test" -NoNewWindow -PassThru -Wait
    Write-Host "✅ Engine verified!" -ForegroundColor $C3
}

Write-Host "`n🚀 LUNOR ENGINE INSTALLED SUCCESSFULLY!" -ForegroundColor $C3
Write-Host "   Restart your browser to activate the changes.`n" -ForegroundColor $C1

Write-Host "Install Path: $InstallDir" -ForegroundColor Gray
Read-Host "Press Enter to finish"
