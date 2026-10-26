# setup-windows.ps1 – Apply or remove chromium-policies.json on Windows.
# Must be run from an Administrator PowerShell session.

#Requires -RunAsAdministrator

param(
    [Alias("s")]
    [switch]$Skip
)

$ErrorActionPreference = "Stop"

# Force UTF-8 for console I/O.
try {
    $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding = $Utf8NoBom
    $OutputEncoding = $Utf8NoBom
} catch { }

$RemoteUrl = "https://raw.githubusercontent.com/SenseiDeElite/chromium-policies.json/refs/heads/main/policies.json"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$JsonPath  = Join-Path $ScriptDir "policies.json"

# Browser display order (used for menu and range parsing)
$BrowserNames = @(
    "Google Chrome",
    "Chromium",
    "Ungoogled Chromium",
    "Microsoft Edge",
    "Vivaldi",
    "Brave",
    "Yandex Browser",
    "Cromite",
    "Helium",
    "Thorium"
)

# Chromium, Ungoogled Chromium, Helium and Thorium all read the stock Chromium key.
# They are listed separately so the menu is unambiguous, but they share one key.
$Targets = @{
    "Google Chrome"      = "HKLM:\SOFTWARE\Policies\Google\Chrome"
    "Chromium"           = "HKLM:\SOFTWARE\Policies\Chromium"
    "Ungoogled Chromium" = "HKLM:\SOFTWARE\Policies\Chromium"
    "Microsoft Edge"     = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    "Vivaldi"            = "HKLM:\SOFTWARE\Policies\Vivaldi"
    "Brave"              = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"
    "Yandex Browser"     = "HKLM:\SOFTWARE\Policies\YandexBrowser"
    "Cromite"            = "HKLM:\SOFTWARE\Policies\Cromite"
    "Helium"             = "HKLM:\SOFTWARE\Policies\Chromium"
    "Thorium"            = "HKLM:\SOFTWARE\Policies\Chromium"
}

# Prints one or more lines to stderr and exits
function Fail {
    param([string[]]$Lines)
    foreach ($line in $Lines) { [Console]::Error.WriteLine($line) }
    exit 1
}

# Reads policies.json as strict UTF-8 and returns the parsed object.
# Throws a clean message if the file is not well-formed JSON or not a non-empty object.
function Read-PolicyFile {
    param([Parameter(Mandatory)][string]$Path)

    try {
        $text = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
    } catch {
        throw "cannot read $Path as UTF-8: $($_.Exception.Message)"
    }
    if ([string]::IsNullOrWhiteSpace($text)) { throw "$Path is empty." }

    # Test-Json (PowerShell 7+) is strict. Windows PowerShell 5.1 has no Test-Json and its
    # ConvertFrom-Json is more lenient, so the structure checks below matter there.
    if (Get-Command Test-Json -ErrorAction SilentlyContinue) {
        if (-not (Test-Json -Json $text -ErrorAction SilentlyContinue)) { throw "$Path is not valid JSON." }
    }
    try   { $root = $text | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "$Path is not valid JSON: $($_.Exception.Message)" }

    if ($root -isnot [pscustomobject])        { throw "$Path must contain a JSON object at the top level." }
    if (@($root.PSObject.Properties).Count -eq 0) { throw "$Path contains no policies." }
    return $root
}

# Turns the parsed policies into a list of { Name, Kind, Value } registry entries.
# Unsupported values (null, floats, ...) are skipped with a warning; if nothing is
# left the install is refused so an existing key is never replaced by an empty one.
function ConvertTo-PolicyPlan {
    param([Parameter(Mandatory)]$Root)

    $plan = [System.Collections.Generic.List[object]]::new()
    foreach ($policy in $Root.PSObject.Properties) {
        $key   = $policy.Name
        $value = $policy.Value
        if ($value -is [bool]) {
            $plan.Add([pscustomobject]@{ Name = $key; Kind = 'DWord'; Value = [int]$value })
        } elseif ($value -is [int] -or $value -is [long]) {
            if ($value -lt [int]::MinValue -or $value -gt [uint32]::MaxValue) {
                Write-Warning "Skipping $key - $value is outside the REG_DWORD range"
                continue
            }
            # Store the Int32 bit pattern so values above 2^31 are accepted on every PowerShell version.
            $dword = if ($value -gt [int]::MaxValue) { [int]($value - 4294967296) } else { [int]$value }
            $plan.Add([pscustomobject]@{ Name = $key; Kind = 'DWord'; Value = $dword })
        } elseif ($value -is [string]) {
            $plan.Add([pscustomobject]@{ Name = $key; Kind = 'String'; Value = $value })
        } elseif ($value -is [array] -or $value -is [pscustomobject] -or $value -is [hashtable]) {
            # Chromium dict/list policies are stored as JSON in a single REG_SZ.
            # -InputObject prevents single-element arrays from being unrolled.
            $json = ConvertTo-Json -InputObject $value -Depth 100 -Compress
            $plan.Add([pscustomobject]@{ Name = $key; Kind = 'String'; Value = $json })
        } else {
            # null, floats, dates are not valid top-level policy values.
            Write-Warning "Skipping $key - unsupported type"
        }
    }
    if ($plan.Count -eq 0) { throw "no usable policies were found in policies.json." }
    return ,$plan.ToArray()
}

# Compares a registry key against the plan. Returns a list of problems (empty = identical).
function Test-PolicyKey {
    param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)]$Key)

    $problems = [System.Collections.Generic.List[string]]::new()
    $names = @($Key.GetValueNames())
    foreach ($n in $names) {
        if ($Plan.Name -cnotcontains $n) { $problems.Add("unexpected value: $n") }
    }
    foreach ($e in $Plan) {
        if ($names -cnotcontains $e.Name) { $problems.Add("missing value: $($e.Name)"); continue }
        $kind = [string]$Key.GetValueKind($e.Name)
        if ($kind -ne $e.Kind) { $problems.Add("$($e.Name): kind is $kind, expected $($e.Kind)"); continue }
        $actual = $Key.GetValue($e.Name, $null, 'DoNotExpandEnvironmentNames')
        if ($actual -cne $e.Value) { $problems.Add("$($e.Name): value does not match") }
    }
    return ,$problems.ToArray()
}

# Stage and verify the plan before replacing the live key; restore it if the swap fails.
# Rename-Item performs a copy + delete, so the swap is not atomic.
function Write-PolicyKey {
    param([Parameter(Mandatory)][string]$RegPath, [Parameter(Mandatory)]$Plan)

    $leaf  = $RegPath.Substring($RegPath.LastIndexOf('\') + 1)
    $stage = "$RegPath.__new"
    $old   = "$RegPath.__old"

    foreach ($stale in @($stage, $old)) {
        if (Test-Path $stale) { Remove-Item -Path $stale -Recurse -Force }
    }

    New-Item -Path $stage -Force | Out-Null
    try {
        foreach ($e in $Plan) {
            Set-ItemProperty -Path $stage -Name $e.Name -Value $e.Value -Type $e.Kind -ErrorAction Stop
        }
        $problems = Test-PolicyKey -Plan $Plan -Key (Get-Item -Path $stage)
        if ($problems.Count -gt 0) {
            throw "verification failed: $($problems -join '; ')"
        }
    } catch {
        Remove-Item -Path $stage -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }

    $hadLive = Test-Path $RegPath
    $movedOld = $false
    try {
        if ($hadLive) { Rename-Item -Path $RegPath -NewName "$leaf.__old"; $movedOld = $true }
        Rename-Item -Path $stage -NewName $leaf
    } catch {
        # Put the previous key back and drop the staging key
        if ($movedOld -and (Test-Path $old) -and -not (Test-Path $RegPath)) {
            try { Rename-Item -Path $old -NewName $leaf }
            catch { Write-Warning "Could not restore the previous policies; they are still stored under $old" }
        }
        Remove-Item -Path $stage -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
    if ($hadLive) { Remove-Item -Path $old -Recurse -Force }
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
    # Download to a temp file and validate it first, so an HTTP error page, a captive-portal
    # page or a truncated download never ends up as policies.json.
    $DlTmp = Join-Path $ScriptDir (".policies.json." + [guid]::NewGuid().ToString("N") + ".tmp")
    & $CurlBin -fsS -o $DlTmp $RemoteUrl
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $DlTmp)) {
        if (Test-Path $DlTmp) { Remove-Item $DlTmp -Force }
        Fail "Error: Failed to fetch policies.json from remote."
    }
    try { $null = Read-PolicyFile -Path $DlTmp }
    catch {
        Remove-Item $DlTmp -Force
        Fail "Error: Downloaded file is not a usable policies.json: $($_.Exception.Message)"
    }
    Move-Item -Path $DlTmp -Destination $JsonPath -Force
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
for ($i = 0; $i -lt $BrowserNames.Count; $i++) {
    Write-Host "  [$($i + 1)] $($BrowserNames[$i])"
}
Write-Host ""
Write-Host "Note: Chromium, Ungoogled Chromium, Helium and Thorium share one registry key, so changes apply to all of them."
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
$processed = @{}

# --- Uninstall ---
if ($action -eq "2") {
    foreach ($name in $selected) {
        $RegPath = $Targets[$name]
        if ($processed.ContainsKey($RegPath)) {
            Write-Host "[$name] Shares $RegPath with $($processed[$RegPath]) - already handled."
            continue
        }
        $processed[$RegPath] = $name
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
    try {
        $plan = ConvertTo-PolicyPlan -Root (Read-PolicyFile -Path $JsonPath)
    } catch {
        Fail "Error: $($_.Exception.Message)", "       Nothing was changed."
    }

    $failed = $false
    foreach ($name in $selected) {
        $RegPath = $Targets[$name]
        Write-Host ""
        Write-Host "Processing $name..."

        # Browsers sharing a registry key are only handled once per run
        if ($processed.ContainsKey($RegPath)) {
            Write-Host "[$name] Shares $RegPath with $($processed[$RegPath]) - already handled."
            continue
        }
        $processed[$RegPath] = $name

        # Confirm overwrite if registry key already exists
        if (Test-Path $RegPath) {
            $confirm = Read-Host "[$name] Policies already exist. Overwrite? [y/N]"
            if ($confirm -notmatch "^[Yy]$") {
                Write-Host "[$name] Skipped."
                continue
            }
        }

        try {
            Write-PolicyKey -RegPath $RegPath -Plan $plan
        } catch {
            Write-Warning "[$name] Failed: $($_.Exception.Message) Existing policies were left in place."
            $failed = $true
            continue
        }
        foreach ($e in $plan) { Write-Host " SET $($e.Name) = $($e.Value)" }
        Write-Host "[$name] Done. $($plan.Count) applied."
        $changed = $true
    }
    if ($failed) {
        Write-Host ""
        Write-Host "One or more browsers failed - see warnings above."
        if ($changed) { Write-Host "Restart your Chromium-based browser and verify at chrome://policy." }
        exit 1
    }
}

if ($changed) {
    Write-Host ""
    Write-Host "Restart your Chromium-based browser and verify at chrome://policy."
}
