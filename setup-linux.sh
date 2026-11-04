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
POLICY_DIRS["Microsoft Edge"]="/etc/opt/edge/policies/managed"
POLICY_DIRS["Vivaldi"]="/etc/chromium/policies/managed"
POLICY_DIRS["Brave"]="/etc/brave/policies/managed"
POLICY_DIRS["Yandex Browser"]="/etc/opt/yandex/browser/policies/managed"
POLICY_DIRS["Cromite"]="/etc/cromite/policies/managed"
POLICY_DIRS["Helium"]="/etc/chromium/policies/managed"
POLICY_DIRS["Thorium"]="/etc/chromium/policies/managed"

# --- Package formats ---
# Native packages use POLICY_DIRS above. Flatpak and Snap builds are sandboxed and need their own
# locations. A browser that is missing from a table below has no known way to load policies in that
# format and is skipped (see the README for why).
FORMAT_LABELS=("Native" "Flatpak" "Snap")
FORMAT_KEYS=(native flatpak snap)

# Flatpak: Chromium and Ungoogled Chromium read policies from extension point v1. An unmanaged
# extension directory under /var/lib/flatpak/extension is discovered without installing an extension.
# Architecture-specific paths are resolved by resolve_flatpak_dirs after Flatpak selection.
# Chrome, Edge, and Brave expose host /etc via --filesystem=host-etc and link the host policy
# directory into the sandbox, so they use the native policy path.
FLATPAK_EXT_ROOT="/var/lib/flatpak/extension"
FLATPAK_EXT_ID="chromium-policies-json"

declare -A FLATPAK_POLICY_DIRS
FLATPAK_POLICY_DIRS["Google Chrome"]="/etc/opt/chrome/policies/managed"
FLATPAK_POLICY_DIRS["Microsoft Edge"]="/etc/opt/edge/policies/managed"
FLATPAK_POLICY_DIRS["Brave"]="/etc/brave/policies/managed"

resolve_flatpak_dirs() {
    local arch
    if ! command -v flatpak &>/dev/null; then
        echo "Error: flatpak is not installed, so the Flatpak policy paths cannot be determined." >&2
        exit 1
    fi
    if ! arch="$(flatpak --default-arch)" || [[ -z "$arch" ]]; then
        echo "Error: 'flatpak --default-arch' failed; cannot determine the Flatpak architecture." >&2
        exit 1
    fi
    FLATPAK_POLICY_DIRS["Chromium"]="$FLATPAK_EXT_ROOT/org.chromium.Chromium.Extension.$FLATPAK_EXT_ID/$arch/1/policies/managed"
    FLATPAK_POLICY_DIRS["Ungoogled Chromium"]="$FLATPAK_EXT_ROOT/io.github.ungoogled_software.ungoogled_chromium.Extension.$FLATPAK_EXT_ID/$arch/1/policies/managed"
}

# Snap: Canonical's Chromium snap reads $SNAP_DATA/policies/managed. $SNAP_DATA is /var/snap/chromium/<rev>
# and "current" points to it. "current" must already exist (i.e. the snap is installed).
declare -A SNAP_ROOTS
SNAP_ROOTS["Chromium"]="/var/snap/chromium/current"
declare -A SNAP_POLICY_DIRS
SNAP_POLICY_DIRS["Chromium"]="${SNAP_ROOTS["Chromium"]}/policies/managed"

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

# Directories created below (including under /var/snap) must be readable by the browser's user.
umask 022

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

# --- Parse selection input into 1-based indices (deduplicated, order preserved) ---
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
            echo "$idx"
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
echo "Note: For native packages, Chromium, Ungoogled Chromium, Vivaldi, Helium and Thorium"
echo "      share /etc/chromium/policies/managed, so changes apply to all of them."
echo ""
read -r -p "Target browser(s): " browser_input </dev/tty

mapfile -t browser_idx < <(parse_selection "$browser_input" "${#BROWSER_NAMES[@]}")
if [[ ${#browser_idx[@]} -eq 0 ]]; then
    echo "No valid selection. Aborting." >&2
    exit 1
fi
selected=()
for idx in "${browser_idx[@]}"; do
    selected+=("${BROWSER_NAMES[$((idx-1))]}")
done

# --- Package format selection ---
echo ""
echo "Package format"
for i in "${!FORMAT_LABELS[@]}"; do
    echo " [$((i+1))] ${FORMAT_LABELS[$i]}"
done
echo ""
echo "Note: Flatpak and Snap are only available for some browsers; the others are skipped."
echo "      Several formats can be selected at once (for example 1,2)."
echo ""
read -r -p "Package format(s) [1]: " format_input </dev/tty
format_input="${format_input:-1}"

mapfile -t format_idx < <(parse_selection "$format_input" "${#FORMAT_KEYS[@]}")
if [[ ${#format_idx[@]} -eq 0 ]]; then
    echo "No valid selection. Aborting." >&2
    exit 1
fi
formats=()
for idx in "${format_idx[@]}"; do
    formats+=("${FORMAT_KEYS[$((idx-1))]}")
    [[ "${FORMAT_KEYS[$((idx-1))]}" == flatpak ]] && resolve_flatpak_dirs
done

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

# format_label NAME FORMAT -> label used in messages
format_label() {
    case "$2" in
        flatpak) echo "$1 (Flatpak)" ;;
        snap)    echo "$1 (Snap)" ;;
        *)       echo "$1" ;;
    esac
}

# prune_empty_dirs DIR STOP -> remove DIR and its parents while empty, never touching STOP or above.
prune_empty_dirs() {
    local dir="$1" stop="$2"
    while [[ "$dir" == "$stop"/* ]]; do
        rmdir -- "$dir" 2>/dev/null || break
        dir="$(dirname -- "$dir")"
    done
}

# --- Process each selected browser ---
changed=false
declare -A processed=()
for fmt in "${formats[@]}"; do
for browser in "${selected[@]}"; do
    name="$(format_label "$browser" "$fmt")"
    prune_stop=""
    snap_root=""
    case "$fmt" in
        native)  policy_dir="${POLICY_DIRS[$browser]:-}" ;;
        flatpak) policy_dir="${FLATPAK_POLICY_DIRS[$browser]:-}"
                 [[ "$policy_dir" == "$FLATPAK_EXT_ROOT"/* ]] && prune_stop="$FLATPAK_EXT_ROOT" ;;
        snap)    policy_dir="${SNAP_POLICY_DIRS[$browser]:-}"
                 snap_root="${SNAP_ROOTS[$browser]:-}" ;;
    esac

    if [[ -z "$policy_dir" ]]; then
        echo ""
        echo "[$name] Not supported – skipped."
        continue
    fi

    echo ""
    echo "Processing $name..."

    # A Snap policy directory must only be created inside an installed snap: if "current" is missing,
    # mkdir -p would create a real directory where snapd expects its symlink.
    if [[ "$fmt" == snap && "$do_install" == true && ! -e "$snap_root" ]]; then
        echo "[$name] Snap is not installed ($snap_root does not exist) – skipped."
        continue
    fi

    policy_dest="$policy_dir/policies.json"

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
        # Drop the Flatpak extension directories this script created, if now empty.
        [[ -n "$prune_stop" ]] && prune_empty_dirs "$policy_dir" "$prune_stop"
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
    # Directories must be root-owned and world-readable (not writable) so the sandboxed browser can read them.
    if [[ "$fmt" == snap ]]; then
        chmod 755 "$snap_root/policies" "$policy_dir"
    fi
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
done

if [[ "$changed" == true ]]; then
    echo ""
    echo "Restart your Chromium-based browser and verify at chrome://policy."
fi
