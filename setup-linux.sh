#!/usr/bin/env bash
# setup-linux.sh – Apply or remove chromium-policies.json on Linux.
# Must be run with elevated privileges: run0 ./setup-linux.sh 
# You can also try sudo-rs, doas, pkexec, sudo and su if run0 (systemd) isn't available.

set -eu

REMOTE_URL="https://raw.githubusercontent.com/SenseiDeElite/chromium-policies.json/refs/heads/main/policies.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_PATH="$SCRIPT_DIR/policies.json"

SKIP=false

# --- Integrity check ---

PYTHON_BIN=""
for _py in python python3; do
    _cand="/usr/bin/$_py"
    if [[ -x "$_cand" ]] \
       && "$_cand" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 6) else 1)' &>/dev/null; then
        PYTHON_BIN="$_cand"
        break
    fi
done
unset _py _cand

# Temp file and verified snapshot used by the atomic install; always removed on exit or interruption.
tmp=""
snap_dir=""
snap=""
trap 'rm -f -- "${tmp:-}"; [[ -n "${snap_dir:-}" ]] && rm -rf -- "$snap_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# check_json FILE -> 0 = well-formed, 1 = problem (reason on stdout). Requires PYTHON_BIN.
# UTF-8 is forced, so the result does not depend on the caller's locale.
check_json() {
    PYTHONUTF8=1 PYTHONIOENCODING=utf-8 "$PYTHON_BIN" - "$1" <<'PYEOF'
import sys, json

def reject_constant(name):
    raise ValueError(f"{name} is not valid JSON")

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f, parse_constant=reject_constant)
except (OSError, UnicodeDecodeError) as e:
    sys.exit(f"cannot read file as UTF-8: {e}")
except ValueError as e:
    sys.exit(f"not valid JSON: {e}")
if not isinstance(data, dict):
    sys.exit("top level must be a JSON object")
if not data:
    sys.exit("the JSON object contains no policies")
PYEOF
}

# Browser display order (used for menu and range parsing)
BROWSER_NAMES=(
    "Google Chrome"
    "Chromium"
    "Ungoogled Chromium"
    "Microsoft Edge"
    "Vivaldi"
    "Brave"
    "Yandex Browser"
    "Cromite"
    "Helium"
    "Thorium"
)

# Chromium, Ungoogled Chromium, Vivaldi, Helium and Thorium read the stock Chromium directory.
# They are listed separately so the menu is unambiguous, but they share one policy file.
declare -A POLICY_DIRS
POLICY_DIRS["Google Chrome"]="/etc/opt/chrome/policies/managed"
POLICY_DIRS["Chromium"]="/etc/chromium/policies/managed"
POLICY_DIRS["Ungoogled Chromium"]="/etc/chromium/policies/managed"
POLICY_DIRS["Microsoft Edge"]="/etc/opt/microsoft/msedge/policies/managed"
POLICY_DIRS["Vivaldi"]="/etc/chromium/policies/managed"
POLICY_DIRS["Brave"]="/etc/brave/policies/managed"
POLICY_DIRS["Yandex Browser"]="/etc/opt/yandex/browser/policies/managed"
POLICY_DIRS["Cromite"]="/etc/cromite/policies/managed"
POLICY_DIRS["Helium"]="/etc/chromium/policies/managed"
POLICY_DIRS["Thorium"]="/etc/chromium/policies/managed"

# --- Usage ---
usage() {
    echo "Usage: $0 [options...]"
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
if [[ "${EUID:-"$(id -u)"}" -ne 0 ]]; then
    echo "Error: This setup script must be run with elevated privileges:" >&2
    echo "       run0 ./setup-linux.sh" >&2
    echo "       You can also try sudo-rs, doas, pkexec, sudo and su if run0 (systemd) isn't available." >&2
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
        echo "Error: curl is not installed. Install it and try again, or download policies.json manually:" >&2
        echo "       $REMOTE_URL" >&2
        exit 1
    fi

    echo "No policies.json found in the script directory."
    echo "Remote: $REMOTE_URL"
    read -r -p "Fetch policies.json from remote? [y/N] " confirm </dev/tty
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted." >&2
        exit 1
    fi
    # Download to a temp file first (and validate it when Python is available), so an HTTP
    # error page, a captive-portal page or a truncated download never becomes policies.json
    dl_tmp="$(mktemp "$SCRIPT_DIR/.policies.json.XXXXXX")" || exit 1
    if ! curl -fsS -o "$dl_tmp" "$REMOTE_URL"; then
        rm -f "$dl_tmp"
        echo "Error: Failed to fetch policies.json from remote." >&2
        exit 1
    fi
    if [[ -n "$PYTHON_BIN" ]] && ! err="$(check_json "$dl_tmp" 2>&1)"; then
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
# Accepts: single (1), comma-separated (1,2), ranges (1-3), or mixed (1,2-4).
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
echo "----------------------------"
for i in "${!BROWSER_NAMES[@]}"; do
    echo " [$((i+1))] ${BROWSER_NAMES[$i]}"
done
echo ""
echo "Note: Chromium, Ungoogled Chromium, Vivaldi, Helium and Thorium share"
echo "      /etc/chromium/policies/managed, so changes apply to all of them."
echo ""
read -r -p "Target browser(s): " browser_input </dev/tty

mapfile -t selected < <(parse_selection "$browser_input" "${#BROWSER_NAMES[@]}")
if [[ ${#selected[@]} -eq 0 ]]; then
    echo "No valid selection. Aborting." >&2
    exit 1
fi

# --- Action selection ---
echo ""
echo " [1] Install"
echo " [2] Uninstall"
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

verify_snapshot() {
    [[ -n "$snap" ]] && return 0
    snap_dir="$(mktemp -d)" || exit 1
    snap="$snap_dir/policies.json"
    if ! cp --reflink=auto -- "$JSON_PATH" "$snap"; then
        echo "Error: could not read $JSON_PATH. Nothing was installed." >&2
        exit 1
    fi
    echo ""
    if [[ -n "$PYTHON_BIN" ]]; then
        if ! err="$(check_json "$snap" 2>&1)"; then
            echo "Error: Integrity check failed for $JSON_PATH: $err" >&2
            echo "       Nothing was installed." >&2
            exit 1
        fi
        echo "Integrity check passed."
    else
        echo "Warning: Python was not found, so no integrity check was performed." >&2
        echo "         Installing anyway. Install Python first if you want policies.json verified." >&2
    fi
}

# --- Process each selected browser ---
changed=false
declare -A processed=()
for name in "${selected[@]}"; do
    policy_dir="${POLICY_DIRS[$name]}"
    policy_dest="$policy_dir/policies.json"

    echo ""
    echo "Processing $name..."

    # Several browsers share one policy file; only handle each file once per run
    if [[ -n "${processed[$policy_dest]+x}" ]]; then
        echo "[$name] Shares $policy_dest with ${processed[$policy_dest]} - already handled."
        continue
    fi
    processed["$policy_dest"]="$name"

    # Uninstall
    if [[ "$do_install" == false ]]; then
        if [[ ! -f "$policy_dest" ]]; then
            echo "[$name] Nothing to remove – $policy_dest does not exist."
            continue
        fi
        read -r -p "[$name] Delete policies at $policy_dest? [y/N] " confirm </dev/tty
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "[$name] Skipped."
            continue
        fi
        rm -f "$policy_dest"
        echo "[$name] Removed: $policy_dest"
        changed=true
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

    # Install atomically
    verify_snapshot
    mkdir -p "$policy_dir"
    tmp="$(mktemp "$policy_dir/.policies.json.XXXXXX")" || exit 1
    if ! cp --reflink=auto -- "$snap" "$tmp"; then
        echo "Error: [$name] could not write to $policy_dir; existing policies left untouched." >&2
        exit 1
    fi
    chmod 644 "$tmp"
    mv -f -- "$tmp" "$policy_dest"
    tmp=""

    echo "[$name] Installed: $policy_dest"
    changed=true
done

if [[ "$changed" == true ]]; then
    echo ""
    echo "Restart your Chromium-based browser and verify at chrome://policy."
fi
