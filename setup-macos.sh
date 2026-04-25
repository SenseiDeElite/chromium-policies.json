#!/usr/bin/env zsh
# setup-macos.sh – Apply or remove chromium-policies.json on macOS.
# Must be run with elevated privileges: sudo ./setup-macos.sh

set -eu

REMOTE_URL="https://raw.githubusercontent.com/SenseiDeElite/chromium-policies.json/refs/heads/main/policies.json"
SCRIPT_DIR="${0:A:h}"
JSON_PATH="$SCRIPT_DIR/policies.json"
PLIST_DIR="/Library/Managed Preferences"

SKIP=false

# Browser display order (used for menu and range parsing)
BROWSER_NAMES=(Chrome Chromium Edge Vivaldi)

declare -A BROWSERS
BROWSERS[Chrome]="com.google.Chrome"
BROWSERS[Chromium]="org.chromium.Chromium"
BROWSERS[Edge]="com.microsoft.Edge"
BROWSERS[Vivaldi]="com.vivaldi.Vivaldi"

# --- Usage ---
usage() {
    echo "Usage: $0 [-s]"
    echo ""
    echo "Options:"
    echo " -s, --skip Skip remote policies.json fetch"
    echo " -h, --help Displays this help message"
    exit 1
}

# --- Argument parsing ---
for arg in "$@"; do
    case "$arg" in
        -s|--skip) SKIP=true ;;
        -h|--help) usage ;;
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
    if ! /usr/bin/curl -sS -o "$JSON_PATH" "$REMOTE_URL"; then
        echo "Error: Failed to fetch policies.json from remote." >&2
        exit 1
    fi
    echo "Fetched successfully."
fi

# --- Verify policies.json is still present before proceeding ---
if [[ ! -f "$JSON_PATH" ]]; then
    echo "Error: policies.json not found at: $JSON_PATH" >&2
    exit 1
fi

# --- Parse selection input into browser names ---
# Accepts: single (1), comma-separated (1,2,3), ranges (1-3), or mixed (1,2-3).
parse_selection() {
    local input="$1"
    local max="$2"
    local -a indices=()

    local IFS=','
    local -a tokens=("${(s:,:)input}")
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
            echo "${BROWSER_NAMES[$((idx-1))]}"
        fi
    done
}

# --- Browser selection ---
echo ""
echo "chromium-policies.json setup"
echo "----------------------------"
echo " [1] Google Chrome"
echo " [2] Chromium"
echo " [3] Microsoft Edge"
echo " [4] Vivaldi"
echo ""
echo " Select one or more: single (1), comma-separated (1,2,3), or range (1-3)"
echo ""
printf "Target browser(s): "
read -r browser_input </dev/tty

selected=("${(@f)$(parse_selection "$browser_input" "${#BROWSER_NAMES[@]}")}")
if [[ ${#selected[@]} -eq 0 ]]; then
    echo "No valid selection. Aborting." >&2
    exit 1
fi

# --- Action selection ---
echo ""
echo "  [1] Install"
echo "  [2] Uninstall"
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

# --- Process each selected browser ---
changed=false
for name in "${selected[@]}"; do
    bundle_id="${BROWSERS[$name]}"
    plist_path="$PLIST_DIR/$bundle_id.plist"

    echo ""
    echo "Processing $name ($bundle_id)..."

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

    # Install
    mkdir -p "$PLIST_DIR"

    python3 - "$JSON_PATH" "$plist_path" <<'PYEOF'
import sys, json, plistlib, os
from pathlib import Path

json_path  = Path(sys.argv[1])
plist_path = Path(sys.argv[2])
plist_tmp  = plist_path.with_suffix(".tmp")

with open(json_path) as f:
    raw = json.load(f)

policies = {}
skipped  = []

for key, value in raw.items():
    # bool must be checked before int (bool is a subclass of int in Python)
    if isinstance(value, (bool, int, str)):
        policies[key] = value
    else:
        skipped.append((key, type(value).__name__))
        continue
    print(f"  SET  {key} = {value}")

try:
    with open(plist_tmp, "wb") as f:
        plistlib.dump(policies, f, fmt=plistlib.FMT_XML, sort_keys=True)
    os.replace(plist_tmp, plist_path)
finally:
    if plist_tmp.exists():
        plist_tmp.unlink(missing_ok=True)

print(f"Written {len(policies)} policies to {plist_path}")
if skipped:
    for k, t in skipped:
        print(f"  SKIPPED  {k} ({t}) - unsupported type", file=sys.stderr)
PYEOF

    chown root:wheel "$plist_path"
    chmod 644 "$plist_path"

    # Validate the plist is well-formed
    if ! plutil -lint "$plist_path" &>/dev/null; then
        echo "[$name] Error: plist validation failed. Removing corrupt file." >&2
        rm -f "$plist_path"
        exit 1
    fi

    echo "[$name] Done."
    changed=true
done

if [[ "$changed" == true ]]; then
    echo ""
    echo "Restart your Chromium-based browser and verify at chrome://policy."
fi
