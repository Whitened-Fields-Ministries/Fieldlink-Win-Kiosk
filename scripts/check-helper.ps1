# CI check for resources/kiosk-admin.ps1, run by Windows PowerShell 5.1 (the
# version that runs it on a kiosk): it must start with a UTF-8 BOM, contain
# nothing but ASCII after it, and parse without errors. See README, "Helper
# rules learned the hard way".
$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '..\resources\kiosk-admin.ps1'
$bytes = [IO.File]::ReadAllBytes($path)
if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) { Write-Error 'kiosk-admin.ps1 must start with a UTF-8 BOM'; exit 1 }
for ($i = 3; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -gt 127) { Write-Error "kiosk-admin.ps1 has a non-ASCII byte at offset $i"; exit 1 } }
$tokens = $null; $errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $path).Path, [ref]$tokens, [ref]$errors)
if ($errors -and $errors.Count) { $errors | ForEach-Object { Write-Host "line $($_.Extent.StartLineNumber): $($_.Message)" }; Write-Error 'kiosk-admin.ps1 does not parse'; exit 1 }
Write-Host "kiosk-admin.ps1: BOM, ASCII and syntax OK (PowerShell $($PSVersionTable.PSVersion))"
