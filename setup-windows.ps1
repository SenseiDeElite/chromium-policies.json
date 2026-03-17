# setup-windows.ps1 — Install or uninstall chromium-policies.json on Windows
# Must be run as Administrator
#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$JsonPath  = Join-Path $ScriptDir "policies.json"
$RegPath   = "HKLM:\SOFTWARE\Policies\Google\Chrome"

# ── Prompt ───────────────────────────────────────────────────────────────────
Write-Host "chromium-policies setup"
Write-Host "-----------------------"
Write-Host "  [1] Install"
Write-Host "  [2] Uninstall"
Write-Host ""
$choice = Read-Host "Choose an option [1/2]"

if ($choice -notin @("1", "2")) {
    Write-Host "Invalid option. Aborting."
    exit 1
}

# ── Uninstall ────────────────────────────────────────────────────────────────
if ($choice -eq "2") {
    if (-not (Test-Path $RegPath)) {
        Write-Host "Nothing to remove — registry key does not exist: $RegPath"
        exit 0
    }
    $confirm = Read-Host "This will delete all Chrome policies from the registry. Continue? [y/N]"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "Aborted."
        exit 0
    }
    Remove-Item -Path $RegPath -Recurse -Force
    Write-Host "Removed: $RegPath"
    Write-Host "Restart Chrome and verify at chrome://policy"
    exit 0
}

# ── Install ──────────────────────────────────────────────────────────────────
if (-not (Test-Path $JsonPath)) {
    Write-Error "policies.json not found at: $JsonPath"
    exit 1
}

if (Test-Path $RegPath) {
    $confirm = Read-Host "Chrome policies already exist in the registry. Overwrite? [y/N]"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "Aborted."
        exit 0
    }
    # Remove first to ensure stale keys from previous installs don't persist
    Remove-Item -Path $RegPath -Recurse -Force
    Write-Host "Cleared existing policies."
}

New-Item -Path $RegPath -Force | Out-Null
Write-Host "Created registry key: $RegPath"

$policies = Get-Content $JsonPath -Raw | ConvertFrom-Json

$applied = 0
$skipped = 0

foreach ($policy in $policies.PSObject.Properties) {
    $name  = $policy.Name
    $value = $policy.Value

    try {
        switch ($value.GetType().Name) {
            "Boolean" {
                $dword = if ($value) { 1 } else { 0 }
                Set-ItemProperty -Path $RegPath -Name $name -Value $dword -Type DWord
            }
            "Int64"   { Set-ItemProperty -Path $RegPath -Name $name -Value $value -Type DWord }
            "Int32"   { Set-ItemProperty -Path $RegPath -Name $name -Value $value -Type DWord }
            "String"  { Set-ItemProperty -Path $RegPath -Name $name -Value $value -Type String }
            default {
                Write-Warning "Skipping '$name': unsupported type '$($value.GetType().Name)'"
                $skipped++
                continue
            }
        }
        Write-Host "  SET  $name = $value"
        $applied++
    } catch {
        Write-Warning "Failed to set '$name': $_"
        $skipped++
    }
}

Write-Host ""
Write-Host "Done. $applied policies applied, $skipped skipped."
Write-Host "Restart Chrome and verify at chrome://policy"
