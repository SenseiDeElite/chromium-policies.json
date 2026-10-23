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

# Prints one or more lines to stderr and exits
function Fail {
    param([string[]]$Lines)
    foreach ($line in $Lines) { [Console]::Error.WriteLine($line) }
    exit 1
}

# --- Parse selection input into browser names ---
# Accepts: single (1), comma-separated (1,2), ranges (1-3), or mixed (1,2-5)
function Parse-Selection {
    param([string]$Selection, [int]$Max)

    $indices = [System.Collections.Generic.List[int]]::new()

    foreach ($token in ($Selection -split ',')) {
        $token = $token.Trim()
        if ($token -match '^(\d+)-(\d+)$') {
            $start = [int]$Matches[1]
            $end   = [int]$Matches[2]
            if ($start -lt 1 -or $end -gt $Max -or $start -gt $end) {
                Write-Warning "Invalid range: $token"
                return $null
            }
            $start..$end | ForEach-Object { $indices.Add($_) }
        } elseif ($token -match '^\d+$') {
            $n = [int]$token
            if ($n -lt 1 -or $n -gt $Max) {
                Write-Warning "Invalid option: $token"
                return $null
            }
            $indices.Add($n)
        } else {
            Write-Warning "Invalid input: $token"
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
        Fail "Error: policies.json not found at: $JsonPath", "       Remove -Skip to allow remote fetch."
    }

    # curl.exe ships in System32 on Windows 10 1803+ and Windows Server 2019+.
    # Verify it is reachable before attempting to use it.
    $CurlBin = $null
    $curlCmd = Get-Command "curl.exe" -ErrorAction SilentlyContinue
    if ($curlCmd) {
        $CurlBin = $curlCmd.Source
    }

    if (-not $CurlBin) {
        Fail "Error: curl.exe is not available on this system.", "       Download policies.json manually from: $RemoteUrl"
    }

    Write-Host "No policies.json found in the script directory."
    Write-Host "Remote: $RemoteUrl"
    $confirm = Read-Host "Fetch policies.json from remote? [y/N]"
    if ($confirm -notmatch "^[Yy]$") {
        Fail "Aborted."
    }
    & $CurlBin -fsS -o $JsonPath $RemoteUrl
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $JsonPath)) {
        if (Test-Path $JsonPath) { Remove-Item $JsonPath -Force }
        Fail "Error: Failed to fetch policies.json from remote."
    }
    Write-Host "Fetched successfully."
}

# --- Verify policies.json is still present before proceeding ---
if (-not (Test-Path $JsonPath)) {
    Fail "Error: policies.json not found at: $JsonPath"
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

$selected = Parse-Selection -Selection $browserInput -Max $BrowserNames.Count
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
    $policies = Get-Content $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

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
                $displayValue = $value
                if ($value -is [bool]) {
                    $dword = if ($value) { 1 } else { 0 }
                    Set-ItemProperty -Path $RegPath -Name $key -Value $dword -Type DWord
                } elseif ($value -is [int] -or $value -is [long]) {
                    Set-ItemProperty -Path $RegPath -Name $key -Value $value -Type DWord
                } elseif ($value -is [string]) {
                    Set-ItemProperty -Path $RegPath -Name $key -Value $value -Type String
                } elseif ($value -is [array] -or $value -is [pscustomobject] -or $value -is [hashtable]) {
                    # Chromium dict/list policies are stored as JSON in a single REG_SZ.
                    # -InputObject prevents single-element arrays from being unrolled.
                    $json = ConvertTo-Json -InputObject $value -Depth 100 -Compress
                    Set-ItemProperty -Path $RegPath -Name $key -Value $json -Type String
                    $displayValue = $json
                } else {
                    # null, floats are not valid top-level policy values.
                    Write-Warning "Skipping $key - unsupported type"
                    $skipped++
                    continue
                }
                Write-Host " SET $key = $displayValue"
                $applied++
            } catch {
                Write-Warning "Failed to set ${key}: $_"
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
