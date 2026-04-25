#!/usr/bin/env bash
# setup-linux.sh - Apply or remove policies.json on Linux.
# Must be run with elevated privileges: sudo ./setup-linux.sh or run0 ./setup-linux.sh

set -eu

REMOTE_URL="https://raw.githubusercontent.com/SenseiDeElite/chromium-policies.json/refs/heads/main/policies.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_PATH="$SCRIPT_DIR/policies.json"

SKIP=false

# Browser display order (used for menu and range parsing)
BROWSER_NAMES=("Chromium/Vivaldi" "Chrome" "Edge")

# Browser name -> policy directory
# Vivaldi reads from /etc/chromium/policies/managed/ on Linux, same as Chromium.
declare -A POLICY_DIRS
POLICY_DIRS["Chromium/Vivaldi"]="/etc/chromium/policies/managed"
POLICY_DIRS["Chrome"]="/etc/opt/chrome/policies/managed"
POLICY_DIRS["Edge"]="/etc/opt/microsoft/msedge/policies/managed"

# --- Usage ---
usage() {
    echo "Usage: $0 [-s]"
    echo ""
    echo "Options:"
    echo "  -s, --skip    Skip remote fetch, require local policies.json"
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
if [[ "${EUID:-"$(id -u)"}" -ne 0 ]]; then
    echo "Error: This script must be run with elevated privileges." >&2
    echo "       Use: sudo ./setup-linux.sh  or  run0 ./setup-linux.sh" >&2
    exit 1
fi

# --- Resolve policies.json ---
if [[ ! -f "$JSON_PATH" ]]; then
    if [[ "$SKIP" == true ]]; then
        echo "Error: policies.json not found at: $JSON_PATH" >&2
        echo "       Remove -s/--skip to allow remote fetch." >&2
        exit 1
    fi

    if ! command -v curl &>/dev/null; then
        echo "Error: curl is not installed. Install it and retry, or download policies.json manually:" >&2
        echo "       $REMOTE_URL" >&2
        exit 1
    fi

    echo "No policies.json found in script directory."
    echo "Remote: $REMOTE_URL"
    read -r -p "Fetch policies.json from remote? [y/N] " confirm </dev/tty
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted." >&2
        exit 1
    fi
    if ! curl -sS -o "$JSON_PATH" "$REMOTE_URL"; then
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
# Accepts: single (1), comma-separated (1,3), ranges (1-3), or mixed (1,2-3)
parse_selection() {
    local input="$1"
    local max="$2"
    local -a indices=()

    IFS=',' read -ra tokens <<< "$input"
    for token in "${tokens[@]}"; do
        token="${token// /}"
        if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start="${BASH_REMATCH[1]}"
            local end="${BASH_REMATCH[2]}"
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
echo "-----------------------------"
echo "  [1] Chromium / Vivaldi"
echo "  [2] Google Chrome"
echo "  [3] Microsoft Edge"
echo ""
echo "  Select one or more: single (1), comma-separated (1,3), or range (1-3)"
echo ""
read -r -p "Target browser(s): " browser_input </dev/tty

mapfile -t selected < <(parse_selection "$browser_input" "${#BROWSER_NAMES[@]}")
if [[ ${#selected[@]} -eq 0 ]]; then
    echo "No valid selection. Aborting." >&2
    exit 1
fi

# --- Action selection ---
echo ""
echo "  [1] Install"
echo "  [2] Uninstall"
echo ""
read -r -p "Choose an action [1/2]: " action </dev/tty

case "$action" in
    1) do_install=true ;;
    2) do_install=false ;;
    *)
        echo "Invalid option. Aborting." >&2
        exit 1
        ;;
esac

# --- Process each selected browser ---
for name in "${selected[@]}"; do
    policy_dir="${POLICY_DIRS[$name]}"
    policy_dest="$policy_dir/policies.json"

    echo ""
    echo "Processing $name..."

    # Uninstall
    if [[ "$do_install" == false ]]; then
        if [[ ! -f "$policy_dest" ]]; then
            echo "[$name] Nothing to remove - $policy_dest does not exist."
            continue
        fi
        read -r -p "[$name] Delete policies at $policy_dest? [y/N] " confirm </dev/tty
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "[$name] Skipped."
            continue
        fi
        rm -f "$policy_dest"
        echo "[$name] Removed: $policy_dest"
        continue
    fi

    # Install: confirm overwrite if policy already exists
    if [[ -f "$policy_dest" ]]; then
        read -r -p "[$name] Policies already exist. Overwrite? [y/N] " confirm </dev/tty
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "[$name] Skipped."
            continue
        fi
    fi

    # Install
    mkdir -p "$policy_dir"
    cp --reflink=auto "$JSON_PATH" "$policy_dest"
    chmod 644 "$policy_dest"

    echo "[$name] Installed: $policy_dest"
done

echo ""
echo "Restart your Chromium-based browser and verify at chrome://policy."
