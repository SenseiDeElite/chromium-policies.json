#!/usr/bin/env zsh
# setup-macos.sh — Install or uninstall chromium-policies.json on macOS
# Must be run with elevated privileges: sudo ./setup-macos.sh

set -eu

SCRIPT_DIR="${0:A:h}"
JSON_PATH="$SCRIPT_DIR/policies.json"
PLIST_DIR="/Library/Managed Preferences"
PLIST_PATH="$PLIST_DIR/com.google.Chrome.plist"

# ── Privilege check ──────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run with sudo." >&2
    exit 1
fi

# ── Prompt ───────────────────────────────────────────────────────────────────
echo "chromium-policies setup"
echo "-----------------------"
echo "  [1] Install"
echo "  [2] Uninstall"
echo ""
printf "Choose an option [1/2]: "
read -r choice

case "$choice" in
    1) ;;
    2) ;;
    *)
        echo "Invalid option. Aborting."
        exit 1
        ;;
esac

# ── Uninstall ────────────────────────────────────────────────────────────────
if [[ "$choice" == "2" ]]; then
    if [[ ! -f "$PLIST_PATH" ]]; then
        echo "Nothing to remove — plist does not exist: $PLIST_PATH"
        exit 0
    fi
    printf "This will delete Chrome policies at:\n  %s\nContinue? [y/N] " "$PLIST_PATH"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    rm -f "$PLIST_PATH"
    echo "Removed: $PLIST_PATH"
    echo "Restart Chrome and verify at chrome://policy"
    exit 0
fi

# ── Install ──────────────────────────────────────────────────────────────────
if [[ ! -f "$JSON_PATH" ]]; then
    echo "Error: policies.json not found at: $JSON_PATH" >&2
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    echo "Error: python3 is required but not found." >&2
    exit 1
fi

if [[ -f "$PLIST_PATH" ]]; then
    printf "Chrome policies already exist at:\n  %s\nOverwrite? [y/N] " "$PLIST_PATH"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

mkdir -p "$PLIST_DIR"

python3 - "$JSON_PATH" "$PLIST_PATH" <<'PYEOF'
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

chown root:wheel "$PLIST_PATH"
chmod 644 "$PLIST_PATH"

echo "Restart Chrome and verify at chrome://policy"
