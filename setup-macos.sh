#!/usr/bin/env zsh
# setup-macos.sh – Apply or remove chromium-policies.json on macOS.
# Must be run with elevated privileges: sudo ./setup-macos.sh
# Note: Cromite has no macOS build, so it is intentionally not listed.

set -eu

# Force UTF-8 for Python regardless of the caller's locale (sudo may reset it).
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8

REMOTE_URL="https://raw.githubusercontent.com/SenseiDeElite/chromium-policies.json/refs/heads/main/policies.json"
SCRIPT_NAME="${0:t}"   # $0 inside a function is the function name in zsh
SCRIPT_DIR="${0:A:h}"
JSON_PATH="$SCRIPT_DIR/policies.json"
PLIST_DIR="/Library/Managed Preferences"

SKIP=false

# Browser display order (used for menu and range parsing)
BROWSER_NAMES=(
    "Google Chrome"
    "Chromium"
    "Ungoogled Chromium"
    "Microsoft Edge"
    "Vivaldi"
    "Brave"
    "Yandex Browser"
    "Helium"
    "Thorium"
)

# Chromium and Ungoogled Chromium share the same bundle ID (and therefore the same plist).
# Compound assignment is required: BROWSERS["Name With Space"]=... would store the quotes in the key in zsh.
typeset -A BROWSERS=(
    "Google Chrome"      "com.google.Chrome"
    "Chromium"           "org.chromium.Chromium"
    "Ungoogled Chromium" "org.chromium.Chromium"
    "Microsoft Edge"     "com.microsoft.Edge"
    "Vivaldi"            "com.vivaldi.Vivaldi"
    "Brave"              "com.brave.Browser"
    "Yandex Browser"     "ru.yandex.desktop.yandex-browser"
    "Helium"             "net.imput.helium"
    "Thorium"            "org.chromium.Thorium"
)

# --- Validate a policies.json file: well-formed JSON, top-level object, not empty ---
# Prints a clean message and returns 1 instead of a Python traceback.
validate_policies_json() {
    python3 - "$1" <<'PYEOF'
import sys, json

def reject_constant(name):
    raise ValueError(f"{name} is not valid JSON")

try:
    with open(sys.argv[1], encoding="utf-8-sig") as f:   # utf-8-sig tolerates a BOM
        raw = json.load(f, parse_constant=reject_constant)
except (OSError, UnicodeDecodeError) as e:
    sys.exit(f"cannot read file as UTF-8: {e}")
except ValueError as e:
    sys.exit(f"not valid JSON: {e}")
if not isinstance(raw, dict):
    sys.exit("top level must be a JSON object")
if not raw:
    sys.exit("the JSON object contains no policies")
PYEOF
}

# --- Usage ---
usage() {
    echo "Usage: $SCRIPT_NAME [options...]"
    echo ""
    echo "Options:"
    echo " -s, --skip Skip remote policies.json fetch"
    echo " -h, --help Displays this help message"
    exit "${1:-1}"
}

# --- Argument parsing ---
for arg in "$@"; do
    case "$arg" in
        -s|--skip) SKIP=true ;;
        -h|--help) usage 0 ;;
        *)
            echo "Error: Unknown option: $arg" >&2
            usage
            ;;
    esac
done

# --- Privilege check ---
if [[ $EUID -ne 0 ]]; then
    echo "Error: This setup script must be run with elevated privileges:" >&2
    echo "       sudo ./setup-macos.sh" >&2
    exit 1
fi

# --- Resolve policies.json ---
if [[ ! -f "$JSON_PATH" ]]; then
    if [[ "$SKIP" == true ]]; then
        echo "Error: policies.json not found at: $JSON_PATH" >&2
        echo "       Remove -s/--skip to allow remote fetch." >&2
        exit 1
    fi

    echo "No policies.json found in script directory."
    echo "Remote: $REMOTE_URL"
    printf "Fetch policies.json from remote? [y/N] "
    read -r confirm </dev/tty
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted." >&2
        exit 1
    fi
    # Download to a temp file and validate it first, so an HTTP error page, a captive-portal
    # page or a truncated download never ends up as policies.json.
    dl_tmp="$(/usr/bin/mktemp "$SCRIPT_DIR/.policies.json.XXXXXX")" || exit 1
    if ! /usr/bin/curl -fsS -o "$dl_tmp" "$REMOTE_URL"; then
        rm -f "$dl_tmp"
        echo "Error: Failed to fetch policies.json from remote." >&2
        exit 1
    fi
    if ! err="$(validate_policies_json "$dl_tmp" 2>&1)"; then
        rm -f "$dl_tmp"
        echo "Error: Downloaded file is not a usable policies.json: $err" >&2
        exit 1
    fi
    chmod 644 "$dl_tmp"
    mv -f "$dl_tmp" "$JSON_PATH"
    echo "Fetched successfully."
fi

# --- Verify policies.json is still present before proceeding ---
if [[ ! -f "$JSON_PATH" ]]; then
    echo "Error: policies.json not found at: $JSON_PATH" >&2
    exit 1
fi

# --- Parse selection input into browser names ---
# Accepts: single (1), comma-separated (1,2), ranges (1-3), or mixed (1,2-5).
parse_selection() {
    local input="$1"
    local max="$2"
    local -a indices=()

    local IFS=','
    local -a tokens=("${(@s:,:)input}")
    for token in "${tokens[@]}"; do
        token="${token// /}"
        if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start="${match[1]}"
            local end="${match[2]}"
            if (( start < 1 || end > max || start > end )); then
                echo "Error: Invalid range: $token" >&2
                return 1
            fi
            for (( i=start; i<=end; i++ )); do
                indices+=("$i")
            done
        elif [[ "$token" =~ ^[0-9]+$ ]]; then
            if (( token < 1 || token > max )); then
                echo "Error: Invalid option: $token" >&2
                return 1
            fi
            indices+=("$token")
        else
            echo "Error: Invalid input: $token" >&2
            return 1
        fi
    done

    # Dedup while preserving order
    local -A seen=()
    for idx in "${indices[@]}"; do
        if [[ -z "${seen[$idx]+x}" ]]; then
            seen[$idx]=1
            echo "${BROWSER_NAMES[$idx]}"
        fi
    done
}

# --- Browser selection ---
echo ""
echo "chromium-policies.json setup"
echo "----------------------------"
for (( i=1; i<=${#BROWSER_NAMES[@]}; i++ )); do
    echo " [$i] ${BROWSER_NAMES[$i]}"
done
echo ""
echo "Note: Chromium and Ungoogled Chromium share one plist, so changes apply to both."
echo ""
printf "Target browser(s): "
read -r browser_input </dev/tty

selected=(${(@f)"$(parse_selection "$browser_input" "${#BROWSER_NAMES[@]}")"})
if [[ ${#selected[@]} -eq 0 ]]; then
    echo "No valid selection. Aborting." >&2
    exit 1
fi

# --- Action selection ---
echo ""
echo " [1] Install"
echo " [2] Uninstall"
echo ""
printf "Choose an action [1/2]: "
read -r action </dev/tty

case "$action" in
    1) do_install=true ;;
    2) do_install=false ;;
    *)
        echo "Invalid option. Aborting." >&2
        exit 1
        ;;
esac

# Private, root-owned snapshot of policies.json
snap_dir=""
snap=""
cleanup() { [[ -n "$snap_dir" ]] && rm -rf -- "$snap_dir"; return 0; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

take_snapshot() {
    [[ -n "$snap" ]] && return 0
    snap_dir="$(/usr/bin/mktemp -d)" || exit 1
    snap="$snap_dir/policies.json"
    if ! /bin/cp -- "$JSON_PATH" "$snap"; then
        echo "Error: could not read $JSON_PATH. Nothing was installed." >&2
        exit 1
    fi
}

# --- Process each selected browser ---
changed=false
typeset -A processed
for name in "${selected[@]}"; do
    bundle_id="${BROWSERS[$name]}"
    plist_path="$PLIST_DIR/$bundle_id.plist"

    echo ""
    echo "Processing $name ($bundle_id)..."

    # Browsers sharing a bundle ID share one plist; only handle each once per run
    if [[ -n "${processed[$bundle_id]-}" ]]; then
        echo "[$name] Shares $bundle_id.plist with ${processed[$bundle_id]} - already handled."
        continue
    fi
    processed[$bundle_id]="$name"

    # Uninstall
    if [[ "$do_install" == false ]]; then
        if [[ ! -f "$plist_path" ]]; then
            echo "[$name] Nothing to remove – plist does not exist."
            continue
        fi
        printf "[%s] Delete policies at %s? [y/N] " "$name" "$plist_path"
        read -r confirm </dev/tty
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "[$name] Skipped."
            continue
        fi
        rm -f "$plist_path"
        echo "[$name] Removed: $plist_path"
        changed=true
        continue
    fi

    # Install: confirm overwrite if plist already exists
    if [[ -f "$plist_path" ]]; then
        printf "[%s] Policies already exist. Overwrite? [y/N] " "$name"
        read -r confirm </dev/tty
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "[$name] Skipped."
            continue
        fi
    fi

    # Install: snapshot once
    take_snapshot
    mkdir -p "$PLIST_DIR"

    python3 - "$snap" "$plist_path" "$JSON_PATH" <<'PYEOF'
import sys, json, plistlib, os, grp, subprocess
from pathlib import Path

json_path  = Path(sys.argv[1])   # snapshot that is actually read (and checked) here
shown_path = sys.argv[3]         # original location, used in messages
plist_path = Path(sys.argv[2])
plist_tmp  = plist_path.with_suffix(".tmp")

def die(msg):
    print(f"Error: {msg}", file=sys.stderr)
    sys.exit(1)

def reject_constant(name):
    raise ValueError(f"{name} is not valid JSON")

try:
    with open(json_path, encoding="utf-8-sig") as f:
        raw = json.load(f, parse_constant=reject_constant)
except (OSError, UnicodeDecodeError) as e:
    die(f"cannot read {shown_path} as UTF-8: {e}")
except ValueError as e:
    die(f"{shown_path} is not valid JSON: {e}")
if not isinstance(raw, dict):
    die("policies.json must contain a JSON object at the top level")

# plistlib stores ints as signed 64-bit (or unsigned up to 2**64-1)
INT_MIN, INT_MAX = -(2**63), 2**64 - 1

def is_plist_safe(value):
    # plistlib can serialize bool/int/float/str and nested list/dict
    # combinations of those, but chokes on JSON null (Python None).
    if value is None:
        return False
    if isinstance(value, bool):
        return True
    if isinstance(value, int):
        return INT_MIN <= value <= INT_MAX
    if isinstance(value, float):
        return value == value and value not in (float("inf"), float("-inf"))
    if isinstance(value, str):
        return True
    if isinstance(value, list):
        return all(is_plist_safe(v) for v in value)
    if isinstance(value, dict):
        return all(isinstance(k, str) and is_plist_safe(v) for k, v in value.items())
    return False

policies = {}
skipped  = []

for key, value in raw.items():
    if is_plist_safe(value):
        policies[key] = value
    else:
        skipped.append((key, type(value).__name__))

# Never replace a working plist with an empty one.
if not policies:
    die("no usable policies were found in policies.json; existing plist left untouched")

def lint(path):
    return subprocess.run(["/usr/bin/plutil", "-lint", str(path)],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

try:
    with open(plist_tmp, "wb") as f:
        plistlib.dump(policies, f, fmt=plistlib.FMT_XML, sort_keys=True)
        f.flush()
        os.fsync(f.fileno())
    # Fix mode/ownership and validate the temp file BEFORE it replaces the live plist,
    # so a failure here can never leave the browser without its previous policies.
    os.chmod(plist_tmp, 0o644)
    os.chown(plist_tmp, 0, grp.getgrnam("wheel").gr_gid)
    if not lint(plist_tmp):
        die("plist validation failed; existing plist left untouched")
    os.replace(plist_tmp, plist_path)
finally:
    if plist_tmp.exists():
        plist_tmp.unlink(missing_ok=True)

for key in sorted(policies):
    print(f" SET {key} = {policies[key]}")
print(f"Written {len(policies)} policies to {plist_path}")
for k, t in skipped:
    print(f" SKIPPED {k} ({t}) – unsupported value", file=sys.stderr)
PYEOF

    echo "[$name] Done."
    changed=true
done

if [[ "$changed" == true ]]; then
    echo ""
    echo "Restart your Chromium-based browser and verify at chrome://policy."
fi
