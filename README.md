# DownloadPilot Engine

Feature-rich download manager and native host helper for the DownloadPilot browser extension.

## Quick Install (PowerShell)

Run the following command in PowerShell to install:

`powershell
irm https://raw.githubusercontent.com/Roodies/dp-engine/main/install.ps1 | iex
`

## Uninstall

Run the same command again to uninstall the engine from your PC.

## Security

The installer verifies the integrity of the downloaded payload using a SHA-256 hash before extraction. If the hash does not match, the installation is aborted and the user is warned.

When updating `payload.zip`, regenerate the hash and update `$PayloadHash` in `install.ps1`:

```powershell
(Get-FileHash -Path payload.zip -Algorithm SHA256).Hash
```
