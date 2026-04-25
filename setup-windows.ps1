# setup-windows.ps1 – Apply or remove chromium-policies.json on Windows.
# Must be run from an Administrator PowerShell session.

#Requires -RunAsAdministrator

param(
    [Alias("s")]
    [switch]$Skip
)

$ErrorActionPreference = "Stop"

$RemoteUrl = "https://raw.githubusercontent.com/SenseiDeElite/chromium-policies.json/refs/heads/main/policies.json"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$JsonPath  = Join-Path $ScriptDir "policies.json"

# Browser display order (used for menu and range parsing)
$BrowserNames = @("Chrome", "Chromium", "Edge", "Vivaldi", "Brave")

$Targets = @{
    "Chrome"   = "HKLM:\SOFTWARE\Policies\Google\Chrome"
    "Chromium" = "HKLM:\SOFTWARE\Policies\Chromium"
    "Edge"     = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    "Vivaldi"  = "HKLM:\SOFTWARE\Policies\Vivaldi"
    "Brave"    = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"
}

# --- Parse selection input into browser names ---
# Accepts: single (1), comma-separated (1,2), ranges (1-3), or mixed (1,2-5)
function Parse-Selection {
    param([string]$Input, [int]$Max)

    $indices = [System.Collections.Generic.List[int]]::new()

    foreach ($token in ($Input -split ',')) {
        $token = $token.Trim()
        if ($token -match '^(\d+)-(\d+)$') {
            $start = [int]$Matches[1]
            $end   = [int]$Matches[2]
            if ($start -lt 1 -or $end -gt $Max -or $start -gt $end) {
                Write-Error "Invalid range: $token"
                return $null
            }
            $start..$end | ForEach-Object { $indices.Add($_) }
        } elseif ($token -match '^\d+$') {
            $n = [int]$token
            if ($n -lt 1 -or $n -gt $Max) {
                Write-Error "Invalid option: $token"
                return $null
            }
            $indices.Add($n)
        } else {
            Write-Error "Invalid input: $token"
            return $null
        }
    }

    # Dedup while preserving order
    $seen = @{}
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($idx in $indices) {
        if (-not $seen.ContainsKey($idx)) {
            $seen[$idx] = $true
            $result.Add($BrowserNames[$idx - 1])
        }
    }
    return $result
}

# --- Resolve policies.json ---
if (-not (Test-Path $JsonPath)) {
    if ($Skip) {
        Write-Error "policies.json not found at: $JsonPath"
        Write-Error "Remove -Skip to allow remote fetch."
        exit 1
    }

    # curl.exe ships in System32 on Windows 10 1803+ and Windows Server 2019+.
    # Verify it is reachable before attempting to use it.
    $CurlBin = $null
    $curlCmd = Get-Command "curl.exe" -ErrorAction SilentlyContinue
    if ($curlCmd) {
        $CurlBin = $curlCmd.Source
    }

    if (-not $CurlBin) {
        Write-Error "curl.exe is not available on this system."
        Write-Error "Download policies.json manually from: $RemoteUrl"
        exit 1
    }

    Write-Host "No policies.json found in the script directory."
    Write-Host "Remote: $RemoteUrl"
    $confirm = Read-Host "Fetch policies.json from remote? [y/N]"
    if ($confirm -notmatch "^[Yy]$") {
        Write-Error "Aborted."
        exit 1
    }
    try {
        & $CurlBin -sS -o $JsonPath $RemoteUrl
        if (-not (Test-Path $JsonPath)) { throw "File not created after fetch." }
    } catch {
        Write-Error "Failed to fetch policies.json from remote: $_"
        exit 1
    }
    Write-Host "Fetched successfully."
}

# --- Verify policies.json is still present before proceeding ---
if (-not (Test-Path $JsonPath)) {
    Write-Error "policies.json not found at: $JsonPath"
    exit 1
}

# --- Browser selection ---
Write-Host ""
Write-Host "chromium-policies.json setup"
Write-Host "----------------------------"
Write-Host "  [1] Google Chrome"
Write-Host "  [2] Chromium"
Write-Host "  [3] Microsoft Edge"
Write-Host "  [4] Vivaldi"
Write-Host "  [5] Brave"
Write-Host ""
$browserInput = Read-Host "Target browser(s)"

$selected = Parse-Selection -Input $browserInput -Max $BrowserNames.Count
if (-not $selected -or $selected.Count -eq 0) {
    Write-Host "No valid selection. Aborting."
    exit 1
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

$changed = $false

# --- Uninstall ---
if ($action -eq "2") {
    foreach ($name in $selected) {
        $RegPath = $Targets[$name]
        if (-not (Test-Path $RegPath)) {
            Write-Host "[$name] Nothing to remove – registry key does not exist."
            continue
        }
        $confirm = Read-Host "[$name] Delete all policies from registry? [y/N]"
        if ($confirm -notmatch "^[Yy]$") {
            Write-Host "[$name] Skipped."
            continue
        }
        Remove-Item -Path $RegPath -Recurse -Force
        Write-Host "[$name] Removed: $RegPath"
        $changed = $true
    }
} else {
    # --- Install ---
    $policies = Get-Content $JsonPath -Raw | ConvertFrom-Json

    foreach ($name in $selected) {
        $RegPath = $Targets[$name]
        Write-Host ""
        Write-Host "Processing $name..."

        # Confirm overwrite if registry key already exists
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
                        Write-Warning "Skipping $key – unsupported type"
                        $skipped++
                        continue
                    }
                }
                Write-Host " SET $key = $value"
                $applied++
            } catch {
                Write-Error "Failed to set ${key}: $_"
                $skipped++
            }
        }
        Write-Host "[$name] Done. $applied applied, $skipped skipped."
        $changed = $true
    }
}

if ($changed) {
    Write-Host ""
    Write-Host "Restart your Chromium-based browser and verify at chrome://policy."
}
