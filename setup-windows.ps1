# setup-windows.ps1 — Apply or remove Chromium policies.json on Windows
# Must be run as Administrator
#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$JsonPath  = Join-Path $ScriptDir "policies.json"

$Targets = @{
    "Chrome"    = "HKLM:\SOFTWARE\Policies\Google\Chrome"
    "Chromium"  = "HKLM:\SOFTWARE\Policies\Chromium"
}

# --- Browser selection ---
Write-Host "Chromium policies setup"
Write-Host "-----------------------"
Write-Host "  [1] Google Chrome"
Write-Host "  [2] Chromium"
Write-Host "  [3] All"
Write-Host ""
$browser = Read-Host "Target browser [1/2/3]"

switch ($browser) {
    "1" { $selected = @("Chrome") }
    "2" { $selected = @("Chromium") }
    "3" { $selected = @("Chrome", "Chromium") }
    default {
        Write-Host "Invalid option. Aborting."
        exit 1
    }
}

# --- Action selection ---
Write-Host ""
Write-Host "  [1] Install"
Write-Host "  [2] Uninstall"
Write-Host ""
$action = Read-Host "Choose an action [1/2]"

if ($action -notin @("1", "2")) {
    Write-Host "Invalid option. Aborting."
    exit 1
}

# --- Uninstall ---
if ($action -eq "2") {
    foreach ($name in $selected) {
        $RegPath = $Targets[$name]
        if (-not (Test-Path $RegPath)) {
            Write-Host "[$name] Nothing to remove - registry key does not exist."
            continue
        }
        $confirm = Read-Host "[$name] Delete all policies from registry? [y/N]"
        if ($confirm -notmatch "^[Yy]$") {
            Write-Host "[$name] Skipped."
            continue
        }
        Remove-Item -Path $RegPath -Recurse -Force
        Write-Host "[$name] Removed: $RegPath"
    }
    Write-Host "Restart your Chromium-based browser and verify at chrome://policy"
    exit 0
}

# --- Install ---
if (-not (Test-Path $JsonPath)) {
    Write-Error "policies.json not found at: $JsonPath"
    exit 1
}

$policies = Get-Content $JsonPath -Raw | ConvertFrom-Json

foreach ($name in $selected) {
    $RegPath = $Targets[$name]
    Write-Host ""
    Write-Host "Applying to $name..."

    if (Test-Path $RegPath) {
        $confirm = Read-Host "[$name] Policies already exist. Overwrite? [y/N]"
        if ($confirm -notmatch "^[Yy]$") {
            Write-Host "[$name] Skipped."
            continue
        }
        Remove-Item -Path $RegPath -Recurse -Force
        Write-Host "[$name] Cleared existing policies."
    }

    New-Item -Path $RegPath -Force | Out-Null

    $applied = 0
    $skipped = 0

    foreach ($policy in $policies.PSObject.Properties) {
        $key   = $policy.Name
        $value = $policy.Value
        try {
            switch ($value.GetType().Name) {
                "Boolean" {
                    $dword = if ($value) { 1 } else { 0 }
                    Set-ItemProperty -Path $RegPath -Name $key -Value $dword -Type DWord
                }
                "Int64"  { Set-ItemProperty -Path $RegPath -Name $key -Value $value -Type DWord }
                "Int32"  { Set-ItemProperty -Path $RegPath -Name $key -Value $value -Type DWord }
                "String" { Set-ItemProperty -Path $RegPath -Name $key -Value $value -Type String }
                default {
                    Write-Warning "Skipping $key - unsupported type"
                    $skipped++
                    continue
                }
            }
            Write-Host "  SET  $key = $value"
            $applied++
        } catch {
            Write-Warning "Failed to set $key"
            $skipped++
        }
    }
    Write-Host "[$name] Done. $applied applied, $skipped skipped."
}

Write-Host ""
Write-Host "Restart your Chromium-based browser and verify at chrome://policy"
