#!/usr/bin/env zsh
# setup-macos.sh - Apply or remove chromium-policies.json on macOS.
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
    echo "Error: This script must be run with elevated privileges." >&2
    exit 1
fi

# --- Browser selection ---
echo "chromium-policies.json setup"
echo "-----------------------"
echo "  [1] Google Chrome"
echo "  [2] Chromium"
echo "  [3] All"
echo ""
printf "Target browser [1/2/3]: "
read -r browser </dev/tty

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
read -r action </dev/tty

case "$action" in
    1) do_install=true ;;
    2) do_install=false ;;
    *)
        echo "Invalid option. Aborting."
        exit 1
        ;;
esac

# --- Pre-flight checks for install ---
if $do_install; then
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
    if ! $do_install; then
        if [[ ! -f "$plist_path" ]]; then
            echo "[$name] Nothing to remove - plist does not exist."
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
        continue
    fi

    # Install
    if [[ -f "$plist_path" ]]; then
        printf "[%s] Policies already exist. Overwrite? [y/N] " "$name"
        read -r confirm </dev/tty
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
plist_tmp  = plist_path.with_suffix(".tmp")

with open(json_path) as f:
    raw = json.load(f)

policies = {}
skipped  = []

for key, value in raw.items():
    if isinstance(value, bool):
        policies[key] = value                  # plistlib → <true/>/<false/>
    elif isinstance(value, float):
        if value.is_integer():
            policies[key] = int(value)         # coerce 1.0 → 1 → <integer/>
        else:
            skipped.append((key, type(value).__name__))
            continue
    elif isinstance(value, (int, str)):
        policies[key] = value
    else:
        skipped.append((key, type(value).__name__))
        continue
    print(f"  SET  {key} = {value}")

try:
    with open(plist_tmp, "wb") as f:
        plistlib.dump(policies, f, fmt=plistlib.FMT_XML, sort_keys=True)
    import os
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
done

echo ""
echo "Restart your Chromium-based browser and verify at chrome://policy."
