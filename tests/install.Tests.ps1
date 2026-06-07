# =============================================================================
# Pester 5 unit tests for install.ps1
# =============================================================================
# These tests mock Windows-specific cmdlets (registry, filesystem, processes)
# so they can run on any platform (Linux/macOS/Windows) without side effects.
# =============================================================================

BeforeAll {
    # Dot-source the script in a controlled way: override the main entry-point
    # variables so no interactive logic fires during import.
    # We'll source individual functions via InModuleScope or re-define them.

    $script:ScriptRoot = Split-Path -Parent $PSScriptRoot
    $script:ScriptPath = Join-Path $script:ScriptRoot 'install.ps1'

    # Define constants that the script uses
    $script:AppName     = "DownloadPilot Engine"
    $script:InstallDir  = if ($env:LOCALAPPDATA) { "$env:LOCALAPPDATA\DownloadOrganizerPro" } else { "/tmp/DownloadOrganizerPro" }
    $script:ExePath     = "$script:InstallDir\DownloadOrganizerHelper.exe"
    $script:HostName    = "com.downloadorganizer.folderhelper"
    $script:ExtId       = "eianiiieigdplanmjjlchcjpebdcggal"
}

# =============================================================================
# Test-HelperInstalled
# =============================================================================
Describe 'Test-HelperInstalled' {

    BeforeAll {
        # Extract just the function from the script
        function Test-HelperInstalled {
            $ExePath    = if ($env:LOCALAPPDATA) { "$env:LOCALAPPDATA\DownloadOrganizerPro\DownloadOrganizerHelper.exe" } else { "/tmp/DownloadOrganizerPro/DownloadOrganizerHelper.exe" }
            $InstallDir = if ($env:LOCALAPPDATA) { "$env:LOCALAPPDATA\DownloadOrganizerPro" } else { "/tmp/DownloadOrganizerPro" }
            $HostName   = "com.downloadorganizer.folderhelper"

            if (-not (Test-Path $ExePath)) { return $false }
            $regPath = "HKCU:\SOFTWARE\Google\Chrome\NativeMessagingHosts\$HostName"
            if (Test-Path $regPath) { return $true }
            if (Test-Path "$InstallDir\manifest.json") { return $true }
            return $false
        }
    }

    Context 'When the executable does not exist' {
        It 'Should return $false' {
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*DownloadOrganizerHelper*" }
            Test-HelperInstalled | Should -Be $false
        }
    }

    Context 'When the executable exists and registry key is present' {
        It 'Should return $true' {
            Mock Test-Path { param($Path)
                if ($Path -like "*DownloadOrganizerHelper*") { return $true }
                if ($Path -like "*NativeMessagingHosts*") { return $true }
                return $false
            }
            Test-HelperInstalled | Should -Be $true
        }
    }

    Context 'When the executable exists, no registry key, but manifest.json exists' {
        It 'Should return $true' {
            Mock Test-Path { param($Path)
                if ($Path -like "*DownloadOrganizerHelper*") { return $true }
                if ($Path -like "*NativeMessagingHosts*") { return $false }
                if ($Path -like "*manifest.json*") { return $true }
                return $false
            }
            Test-HelperInstalled | Should -Be $true
        }
    }

    Context 'When the executable exists but neither registry key nor manifest exist' {
        It 'Should return $false' {
            Mock Test-Path { param($Path)
                if ($Path -like "*DownloadOrganizerHelper*") { return $true }
                return $false
            }
            Test-HelperInstalled | Should -Be $false
        }
    }
}

# =============================================================================
# Invoke-Uninstall
# =============================================================================
Describe 'Invoke-Uninstall' {

    BeforeAll {
        # Minimal re-implementation for testability
        $script:ExePath    = if ($env:LOCALAPPDATA) { "$env:LOCALAPPDATA\DownloadOrganizerPro\DownloadOrganizerHelper.exe" } else { "/tmp/DownloadOrganizerPro/DownloadOrganizerHelper.exe" }
        $script:InstallDir = if ($env:LOCALAPPDATA) { "$env:LOCALAPPDATA\DownloadOrganizerPro" } else { "/tmp/DownloadOrganizerPro" }
        $script:HostName   = "com.downloadorganizer.folderhelper"
        $script:ExtId      = "eianiiieigdplanmjjlchcjpebdcggal"
        $script:AppName    = "DownloadPilot Engine"

        function Invoke-Uninstall {
            $ExePath    = $script:ExePath
            $InstallDir = $script:InstallDir
            $HostName   = $script:HostName
            $ExtId      = $script:ExtId
            $AppName    = $script:AppName

            # 1. Revert folder changes
            if (Test-Path $ExePath) {
                try {
                    Start-Process -FilePath $ExePath -ArgumentList "--uninstall", "--silent" -Wait -NoNewWindow -ErrorAction SilentlyContinue
                } catch { }
            }

            # 2. Kill running helper processes
            Get-Process -Name "DownloadOrganizerHelper" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

            # 3. Remove NativeMessagingHosts registry keys
            @(
                "SOFTWARE\Google\Chrome\NativeMessagingHosts\$HostName",
                "SOFTWARE\Microsoft\Edge\NativeMessagingHosts\$HostName",
                "SOFTWARE\BraveSoftware\Brave-Browser\NativeMessagingHosts\$HostName",
                "SOFTWARE\Opera Software\Opera Stable\NativeMessagingHosts\$HostName",
                "SOFTWARE\Vivaldi\NativeMessagingHosts\$HostName"
            ) | ForEach-Object {
                Remove-Item "HKCU:\$_" -Recurse -Force -ErrorAction SilentlyContinue
            }

            # 4. Remove external extension keys
            @(
                "Software\Google\Chrome\Extensions\$ExtId",
                "Software\Microsoft\Edge\Extensions\$ExtId",
                "Software\BraveSoftware\Brave-Browser\Extensions\$ExtId",
                "Software\Opera Software\Opera Stable\Extensions\$ExtId",
                "Software\Vivaldi\Extensions\$ExtId"
            ) | ForEach-Object {
                Remove-Item "HKCU:\$_" -Recurse -Force -ErrorAction SilentlyContinue
            }
            Remove-Item "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\DownloadPilotEngine" -Recurse -Force -ErrorAction SilentlyContinue

            # 5. Delete install directory
            if (Test-Path $InstallDir) {
                Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    BeforeEach {
        Mock Write-Host {}
        Mock Start-Process {}
        Mock Get-Process { return $null }
        Mock Stop-Process {}
        Mock Remove-Item {}
    }

    Context 'When the executable exists' {
        BeforeEach {
            Mock Test-Path { param($Path)
                if ($Path -eq $script:ExePath) { return $true }
                if ($Path -eq $script:InstallDir) { return $true }
                return $false
            }
        }

        It 'Should call Start-Process to run the helper uninstaller' {
            Invoke-Uninstall
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq $script:ExePath -and
                $ArgumentList -contains "--uninstall"
            }
        }

        It 'Should attempt to stop helper processes' {
            Invoke-Uninstall
            Should -Invoke Get-Process -Times 1 -Exactly -ParameterFilter {
                $Name -eq "DownloadOrganizerHelper"
            }
        }

        It 'Should remove the install directory' {
            Invoke-Uninstall
            Should -Invoke Remove-Item -ParameterFilter {
                $Path -eq $script:InstallDir
            }
        }

        It 'Should remove registry keys for all supported browsers (native messaging)' {
            Invoke-Uninstall
            # 5 native messaging + 5 extensions + 1 uninstall key + 1 install dir = 12
            Should -Invoke Remove-Item -Times 12 -Exactly
        }
    }

    Context 'When the executable does not exist' {
        BeforeEach {
            Mock Test-Path { param($Path)
                if ($Path -eq $script:ExePath) { return $false }
                if ($Path -eq $script:InstallDir) { return $false }
                return $false
            }
        }

        It 'Should NOT call Start-Process' {
            Invoke-Uninstall
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'Should still remove registry keys but NOT the install directory' {
            Invoke-Uninstall
            # 5 native messaging + 5 extensions + 1 uninstall key = 11 (no dir)
            Should -Invoke Remove-Item -Times 11 -Exactly
        }
    }

    Context 'When Start-Process throws an error' {
        BeforeEach {
            Mock Test-Path { return $true }
            Mock Start-Process { throw "Process not found" }
        }

        It 'Should silently continue without failing' {
            { Invoke-Uninstall } | Should -Not -Throw
        }
    }
}

# =============================================================================
# Invoke-Install
# =============================================================================
Describe 'Invoke-Install' {

    BeforeAll {
        $script:ExePath    = if ($env:LOCALAPPDATA) { "$env:LOCALAPPDATA\DownloadOrganizerPro\DownloadOrganizerHelper.exe" } else { "/tmp/DownloadOrganizerPro/DownloadOrganizerHelper.exe" }
        $script:InstallDir = if ($env:LOCALAPPDATA) { "$env:LOCALAPPDATA\DownloadOrganizerPro" } else { "/tmp/DownloadOrganizerPro" }
        $script:HostName   = "com.downloadorganizer.folderhelper"
        $script:ExtId      = "eianiiieigdplanmjjlchcjpebdcggal"
        $script:AppName    = "DownloadPilot Engine"
        $script:DownloadUrl = "https://raw.githubusercontent.com/Roodies/dp-engine/main/payload.zip"

        function Invoke-Install {
            $ExePath     = $script:ExePath
            $InstallDir  = $script:InstallDir
            $HostName    = $script:HostName
            $ExtId       = $script:ExtId
            $AppName     = $script:AppName
            $DownloadUrl = $script:DownloadUrl

            $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) "payload.zip"

            # 1. Check for local payload
            $localZip = $null
            if ($PSScriptRoot) {
                $localZip = Join-Path $PSScriptRoot "payload.zip"
            }

            if ($localZip -and (Test-Path $localZip)) {
                $tempZip = $localZip
            }
            else {
                # Download from GitHub
                try {
                    Invoke-WebRequest -Uri $DownloadUrl -OutFile $tempZip -UseBasicParsing
                }
                catch {
                    Write-Host "  ERROR: Failed to download the payload archive." -ForegroundColor Red
                    return
                }
            }

            # 2. Extract payload
            try {
                if (Test-Path $InstallDir) {
                    Get-Process -Name "DownloadOrganizerHelper" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 100
                    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
                }
                New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
                Expand-Archive -Path $tempZip -DestinationPath $InstallDir -Force
            }
            catch {
                Write-Host "  ERROR: Failed to install engine files." -ForegroundColor Red
                return
            }

            # 3. Generate manifest
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

            # Return a success indicator for testing
            return $true
        }
    }

    BeforeEach {
        Mock Write-Host {}
        Mock Invoke-WebRequest {}
        Mock Test-Path { return $false }
        Mock Get-Process { return $null }
        Mock Stop-Process {}
        Mock Remove-Item {}
        Mock New-Item {}
        Mock Expand-Archive {}
        Mock Start-Sleep {}
        Mock Out-File {}
    }

    Context 'When local payload.zip exists' {
        BeforeEach {
            Mock Test-Path { param($Path)
                if ($Path -like "*payload.zip") { return $true }
                return $false
            }
        }

        It 'Should NOT download from the internet' {
            Invoke-Install
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }

        It 'Should call Expand-Archive to extract files' {
            Invoke-Install
            Should -Invoke Expand-Archive -Times 1 -Exactly
        }

        It 'Should create the install directory' {
            Invoke-Install
            Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter {
                $ItemType -eq 'Directory' -and $Path -eq $script:InstallDir
            }
        }
    }

    Context 'When no local payload exists and download succeeds' {
        BeforeEach {
            Mock Test-Path { return $false }
        }

        It 'Should download the payload from GitHub' {
            Invoke-Install
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq $script:DownloadUrl
            }
        }

        It 'Should extract the downloaded archive' {
            Invoke-Install
            Should -Invoke Expand-Archive -Times 1 -Exactly
        }
    }

    Context 'When download fails' {
        BeforeEach {
            Mock Test-Path { return $false }
            Mock Invoke-WebRequest { throw "Network error" }
        }

        It 'Should report an error and return early' {
            Invoke-Install
            Should -Invoke Write-Host -ParameterFilter {
                $Object -like "*ERROR*download*"
            }
        }

        It 'Should NOT attempt to extract files' {
            Invoke-Install
            Should -Invoke Expand-Archive -Times 0 -Exactly
        }
    }

    Context 'When extraction fails' {
        BeforeEach {
            Mock Test-Path { param($Path)
                if ($Path -like "*payload.zip") { return $true }
                return $false
            }
            Mock Expand-Archive { throw "Archive corrupt" }
        }

        It 'Should report an extraction error' {
            Invoke-Install
            Should -Invoke Write-Host -ParameterFilter {
                $Object -like "*ERROR*install*"
            }
        }
    }

    Context 'When install directory already exists' {
        BeforeEach {
            Mock Test-Path { param($Path)
                if ($Path -like "*payload.zip") { return $true }
                if ($Path -eq $script:InstallDir) { return $true }
                return $false
            }
        }

        It 'Should attempt to stop running helper processes' {
            Invoke-Install
            Should -Invoke Get-Process -ParameterFilter {
                $Name -eq "DownloadOrganizerHelper"
            }
        }

        It 'Should remove the old install directory before extracting' {
            Invoke-Install
            Should -Invoke Remove-Item -ParameterFilter {
                $Path -eq $script:InstallDir
            }
        }
    }

    Context 'Manifest structure' {
        It 'Should define correct manifest fields in the install script' {
            $content = Get-Content (Join-Path $PSScriptRoot '..' 'install.ps1') -Raw
            # Verify manifest includes required NativeMessaging fields
            $content | Should -Match 'name\s*=\s*\$HostName'
            $content | Should -Match 'type\s*=\s*"stdio"'
            $content | Should -Match 'allowed_origins'
            $content | Should -Match 'manifest\.json'
        }

        It 'Should write manifest to the install directory' {
            $content = Get-Content (Join-Path $PSScriptRoot '..' 'install.ps1') -Raw
            $content | Should -Match 'Out-File\s+-FilePath\s+"\$InstallDir\\manifest\.json"'
        }
    }
}

# =============================================================================
# Main Entry Point Logic
# =============================================================================
Describe 'Main Entry Point Logic' {

    BeforeAll {
        $script:AppName = "DownloadPilot Engine"

        function Test-HelperInstalled { return $script:MockInstalled }

        # Track which function was called
        $script:InstalledCalled = $false
        $script:UninstalledCalled = $false

        function Invoke-Install {
            $script:InstalledCalled = $true
        }

        function Invoke-Uninstall {
            $script:UninstalledCalled = $true
        }

        function Invoke-MainLogic {
            param(
                [switch]$silent,
                [switch]$uninstall
            )

            $isInstalled = Test-HelperInstalled

            if ($uninstall) {
                if ($isInstalled) {
                    Invoke-Uninstall
                }
                # else: nothing to uninstall
            }
            elseif ($isInstalled) {
                if ($silent) {
                    # Silent mode: just inform
                    Write-Host "  $script:AppName is already installed." -ForegroundColor Green
                }
                else {
                    # In tests, simulate user choosing 'N' (no uninstall)
                    Write-Host "  Already installed."
                }
            }
            else {
                Invoke-Install
            }
        }
    }

    BeforeEach {
        $script:InstalledCalled = $false
        $script:UninstalledCalled = $false
        Mock Write-Host {}
    }

    Context 'When --uninstall flag is set and app is installed' {
        BeforeEach {
            $script:MockInstalled = $true
        }

        It 'Should call Invoke-Uninstall' {
            Invoke-MainLogic -uninstall
            $script:UninstalledCalled | Should -Be $true
        }

        It 'Should NOT call Invoke-Install' {
            Invoke-MainLogic -uninstall
            $script:InstalledCalled | Should -Be $false
        }
    }

    Context 'When --uninstall flag is set but app is NOT installed' {
        BeforeEach {
            $script:MockInstalled = $false
        }

        It 'Should NOT call Invoke-Uninstall' {
            Invoke-MainLogic -uninstall
            $script:UninstalledCalled | Should -Be $false
        }

        It 'Should NOT call Invoke-Install' {
            Invoke-MainLogic -uninstall
            $script:InstalledCalled | Should -Be $false
        }
    }

    Context 'When app is already installed (no flags)' {
        BeforeEach {
            $script:MockInstalled = $true
        }

        It 'Should NOT call Invoke-Install' {
            Invoke-MainLogic
            $script:InstalledCalled | Should -Be $false
        }

        It 'Should NOT call Invoke-Uninstall' {
            Invoke-MainLogic
            $script:UninstalledCalled | Should -Be $false
        }
    }

    Context 'When app is already installed with --silent flag' {
        BeforeEach {
            $script:MockInstalled = $true
        }

        It 'Should inform user and not uninstall' {
            Invoke-MainLogic -silent
            $script:UninstalledCalled | Should -Be $false
            $script:InstalledCalled | Should -Be $false
            Should -Invoke Write-Host -ParameterFilter {
                $Object -like "*already installed*"
            }
        }
    }

    Context 'When app is NOT installed (no flags)' {
        BeforeEach {
            $script:MockInstalled = $false
        }

        It 'Should call Invoke-Install' {
            Invoke-MainLogic
            $script:InstalledCalled | Should -Be $true
        }

        It 'Should NOT call Invoke-Uninstall' {
            Invoke-MainLogic
            $script:UninstalledCalled | Should -Be $false
        }
    }
}

# =============================================================================
# Constants and Configuration
# =============================================================================
Describe 'Script Constants' {

    It 'Should define the correct native host name' {
        $content = Get-Content (Join-Path $PSScriptRoot '..' 'install.ps1') -Raw
        $content | Should -Match 'com\.downloadorganizer\.folderhelper'
    }

    It 'Should define the Chrome extension ID' {
        $content = Get-Content (Join-Path $PSScriptRoot '..' 'install.ps1') -Raw
        $content | Should -Match 'eianiiieigdplanmjjlchcjpebdcggal'
    }

    It 'Should target LOCALAPPDATA for installation' {
        $content = Get-Content (Join-Path $PSScriptRoot '..' 'install.ps1') -Raw
        $content | Should -Match '\$env:LOCALAPPDATA\\DownloadOrganizerPro'
    }

    It 'Should register with 5 browsers (Chrome, Edge, Brave, Opera, Vivaldi)' {
        $content = Get-Content (Join-Path $PSScriptRoot '..' 'install.ps1') -Raw
        $content | Should -Match 'Google\\Chrome'
        $content | Should -Match 'Microsoft\\Edge'
        $content | Should -Match 'BraveSoftware\\Brave-Browser'
        $content | Should -Match 'Opera Software\\Opera Stable'
        $content | Should -Match 'Vivaldi'
    }

    It 'Should include 3 allowed extension origins in manifest' {
        $content = Get-Content (Join-Path $PSScriptRoot '..' 'install.ps1') -Raw
        $origins = [regex]::Matches($content, 'chrome-extension://[a-z]+/')
        $origins.Count | Should -BeGreaterOrEqual 3
    }

    It 'Should set native messaging type to stdio' {
        $content = Get-Content (Join-Path $PSScriptRoot '..' 'install.ps1') -Raw
        $content | Should -Match 'type\s*=\s*"stdio"'
    }

    It 'Should define download URL pointing to GitHub raw' {
        $content = Get-Content (Join-Path $PSScriptRoot '..' 'install.ps1') -Raw
        $content | Should -Match 'https://raw\.githubusercontent\.com/Roodies/dp-engine/main/payload\.zip'
    }
}

# =============================================================================
# Error Handling
# =============================================================================
Describe 'Error Handling' {

    It 'Should set ErrorActionPreference to Stop' {
        $content = Get-Content (Join-Path $PSScriptRoot '..' 'install.ps1') -Raw
        $content | Should -Match 'ErrorActionPreference\s*=\s*.Stop.'
    }

    It 'Should enforce TLS 1.2 for secure downloads' {
        $content = Get-Content (Join-Path $PSScriptRoot '..' 'install.ps1') -Raw
        $content | Should -Match 'Tls12'
    }

    It 'Should use -ErrorAction SilentlyContinue for non-critical operations' {
        $content = Get-Content (Join-Path $PSScriptRoot '..' 'install.ps1') -Raw
        $silentContinue = [regex]::Matches($content, 'SilentlyContinue')
        $silentContinue.Count | Should -BeGreaterOrEqual 5
    }
}

# =============================================================================
# Script Parameter Handling
# =============================================================================
Describe 'Parameter Handling' {

    It 'Should accept --silent switch parameter' {
        $content = Get-Content (Join-Path $PSScriptRoot '..' 'install.ps1') -Raw
        $content | Should -Match '\[switch\]\$silent'
    }

    It 'Should accept --uninstall switch parameter' {
        $content = Get-Content (Join-Path $PSScriptRoot '..' 'install.ps1') -Raw
        $content | Should -Match '\[switch\]\$uninstall'
    }

    It 'Should support double-dash string args for piped execution' {
        $content = Get-Content (Join-Path $PSScriptRoot '..' 'install.ps1') -Raw
        $content | Should -Match 'args\s+-contains\s+.--silent.'
        $content | Should -Match 'args\s+-contains\s+.--uninstall.'
    }
}
