#!/usr/bin/env zsh
# setup-macos.sh - Apply or remove Chromium policies.json on macOS
# Must be run with elevated privileges: sudo ./setup-macos.sh

set -eu

SCRIPT_DIR="${0:A:h}"
JSON_PATH="$SCRIPT_DIR/policies.json"
PLIST_DIR="/Library/Managed Preferences"

declare -A BROWSERS
BROWSERS[Chrome]="com.google.Chrome"
BROWSERS[Chromium]="org.chromium.Chromium"

# --- Privilege check ---
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run with sudo." >&2
    exit 1
fi

# --- Browser selection ---
echo "Chromium policies setup"
echo "-----------------------"
echo "  [1] Google Chrome"
echo "  [2] Chromium"
echo "  [3] All"
echo ""
printf "Target browser [1/2/3]: "
read -r browser

case "$browser" in
    1) selected=(Chrome) ;;
    2) selected=(Chromium) ;;
    3) selected=(Chrome Chromium) ;;
    *)
        echo "Invalid option. Aborting."
        exit 1
        ;;
esac

# --- Action selection ---
echo ""
echo "  [1] Install"
echo "  [2] Uninstall"
echo ""
printf "Choose an action [1/2]: "
read -r action

case "$action" in
    1) ;;
    2) ;;
    *)
        echo "Invalid option. Aborting."
        exit 1
        ;;
esac

# --- python3 check (install only) ---
if [[ "$action" == "1" ]]; then
    if [[ ! -f "$JSON_PATH" ]]; then
        echo "Error: policies.json not found at: $JSON_PATH" >&2
        exit 1
    fi
    if ! command -v python3 &>/dev/null; then
        echo "Error: python3 is required but not found." >&2
        exit 1
    fi
fi

# --- Process each selected browser ---
for name in "${selected[@]}"; do
    bundle_id="${BROWSERS[$name]}"
    plist_path="$PLIST_DIR/$bundle_id.plist"

    echo ""
    echo "Processing $name ($bundle_id)..."

    # Uninstall
    if [[ "$action" == "2" ]]; then
        if [[ ! -f "$plist_path" ]]; then
            echo "[$name] Nothing to remove - plist does not exist."
            continue
        fi
        printf "[%s] Delete policies at %s? [y/N] " "$name" "$plist_path"
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "[$name] Skipped."
            continue
        fi
        rm -f "$plist_path"
        echo "[$name] Removed: $plist_path"
        continue
    fi

    # Install
    if [[ -f "$plist_path" ]]; then
        printf "[%s] Policies already exist. Overwrite? [y/N] " "$name"
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "[$name] Skipped."
            continue
        fi
    fi

    mkdir -p "$PLIST_DIR"

    python3 - "$JSON_PATH" "$plist_path" <<'PYEOF'
import sys, json, plistlib
from pathlib import Path

json_path  = Path(sys.argv[1])
plist_path = Path(sys.argv[2])

with open(json_path) as f:
    policies = json.load(f)

with open(plist_path, "wb") as f:
    plistlib.dump(policies, f, fmt=plistlib.FMT_XML, sort_keys=True)

print(f"Written {len(policies)} policies to {plist_path}")
PYEOF

    chown root:wheel "$plist_path"
    chmod 644 "$plist_path"
    echo "[$name] Done."
done

echo ""
echo "Restart your Chromium-based browser and verify at chrome://policy"
