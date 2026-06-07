#!/bin/bash
# main.sh

source mvenv/bin/activate

# Use local gplaydl from dependency/
export PYTHONPATH="${PYTHONPATH}:$(pwd)/dependency/gplaydl"

# ── Syslog-style logging ──────────────────────────────────────────────
SUBFOLDER="Playstore-Downloads"
MAIN_LOG="$SUBFOLDER/main.log"
SCRIPT_NAME="$(basename "$0")"

_syslog() {
    local level="$1"
    shift
    local msg="$*"
    local ts
    ts="$(date '+%b %d %H:%M:%S')"
    local line="${ts} $(hostname) ${SCRIPT_NAME}[$$]: ${level}: ${msg}"
    echo "$line"
    { echo "$line" >> "$MAIN_LOG"; } 2>/dev/null || true
}

log_info()     { _syslog "INFO"    "$@"; }
log_warn()     { _syslog "WARN"    "$@"; }
log_error() { _syslog "ERROR" "$@"; }
# ───────────────────────────────────────────────────────────────────────

#set -euo pipefail

# Parse --package-name argument (mandatory)
PACKAGE_NAME=""
DEVICE_PROFILE=""
DISPENSER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
         --package-name)
            if [[ -z "${2:-}" ]]; then
                log_error "--package-name requires a value."
                log_error "Usage: bash main.sh --package-name <android.package.name> [--subfolder <dir>] [--device-profile <path>] [--dispenser-url <url>]"
                exit 1
            fi
            PACKAGE_NAME="$2"
            shift 2
             ;;
           --device-profile)
            if [[ -z "${2:-}" ]]; then
                log_error "--device-profile requires a value."
                log_error "Usage: bash main.sh --package-name <android.package.name> --subfolder <dir> --device-profile <path>"
                exit 1
            fi
            if [[ ! -f "$2" ]]; then
                log_error "Device profile file not found: $2"
                exit 1
            fi
            DEVICE_PROFILE="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
            shift 2
                ;;
                --subfolder)
            if [[ -z "${2:-}" ]]; then
                log_error "--subfolder requires a value."
                log_error "Usage: bash main.sh --package-name <android.package.name> --subfolder <dir>"
                exit 1
            fi
            SUBFOLDER="$2"
            shift 2
                       ;;
            --dispenser-url)
            if [[ -z "${2:-}" ]]; then
                log_error "--dispenser-url requires a value."
                log_error "Usage: bash main.sh --package-name <android.package.name> --dispenser-url <url>"
                exit 1
            fi
            DISPENSER="$2"
            if ! [[ "$DISPENSER" =~ ^https?:// ]]; then
                log_error "a URL must be provided to --dispenser-url, e.g: http://your-dispenser.com/api/auth"
                exit 1
            fi
            shift 2
                 ;;
         *)
            log_error "Usage: bash main.sh --package-name <android.package.name> [--subfolder <dir>] [--device-profile <path>] [--dispenser-url <url>]"
            log_error "  e.g: bash main.sh --package-name com.microsoft.emmx"
            log_error "  e.g: bash main.sh --package-name com.samsung.android.knox.kpu --device-profile dependency/gplaydl/gplaydl/profiles/D2.properties --dispenser-url http://192.168.1.42:3000/api/auth"
            exit 1
             ;;
    esac
done

if [[ -z "$PACKAGE_NAME" ]]; then
    log_error "--package-name argument is required."
    log_error "Usage: bash main.sh --package-name <android.package.name> [--subfolder <dir>] [--device-profile <path>] [--dispenser-url <url>]"
    log_error "  e.g: bash main.sh --package-name com.microsoft.emmx"
    log_error "  e.g: bash main.sh --package-name com.samsung.android.knox.kpu --device-profile dependency/gplaydl/gplaydl/profiles/D2.properties --dispenser-url http://192.168.1.42:3000/api/auth"
    exit 1
fi
mkdir -p "$SUBFOLDER"

log_info "Starting — package: ${PACKAGE_NAME}"
if [[ -n "$DEVICE_PROFILE" ]]; then
    log_info "Device profile: ${DEVICE_PROFILE}"
fi
if [[ -n "$DISPENSER" ]]; then
    log_info "Dispenser: ${DISPENSER}"
fi

START_DIR="$(pwd)"
BASE_DIR="$SUBFOLDER"
STATE_FILE="$BASE_DIR/.last_version"
LOG_FILE="$BASE_DIR/logs.txt"
PLAYDL_STDERR="$START_DIR/$SUBFOLDER/main_error.log"

# Record start time
START_EPOCH=$(date +%s)
START_DATE=$(date +%Y/%m/%d)
START_TIME=$(date +%H:%M:%S)

# If log file doesn't exist, create it and add header
if [[ ! -f "$LOG_FILE" ]]; then
    echo "date,time,version,is_new,elapsed_seconds,result" > "$LOG_FILE"
fi

# 1. Get current version from Play Store
CURRENT_VERSION=$(python3 -c "
from google_play_scraper import app
result = app('$PACKAGE_NAME', lang='en', country='us')
print(result['version'])
")

TARGET_DIR="$BASE_DIR/${PACKAGE_NAME}_${CURRENT_VERSION}"

# 2. Check if we already have this version
#if [[ -f "$STATE_FILE" ]] && grep -q "^$CURRENT_VERSION$" "$STATE_FILE"; then
if [[ -d "${TARGET_DIR}" ]]; then
    log_info "Version ${CURRENT_VERSION} already downloaded"

    cd "$TARGET_DIR"
    IS_NEW=false
else
    # 3. Download APK via gplaydl [[2]]
    log_info "Version ${CURRENT_VERSION} not found locally — starting download"
    mkdir -p "$TARGET_DIR"
    
    log_info "Will change directory to ${TARGET_DIR} for download"
    cd "$TARGET_DIR"

    # First-time auth (anonymous via Aurora Store)
    if [[ -n "$DEVICE_PROFILE" ]]; then
        log_info "Authenticating with device profile ${DEVICE_PROFILE}"
        log_info "Will exec: python -m gplaydl auth --profile \"$DEVICE_PROFILE\" --dispenser \"$DISPENSER\""
        python -m gplaydl auth --profile "$DEVICE_PROFILE" --dispenser "$DISPENSER" 2>"$PLAYDL_STDERR" || true
    else
        log_info "Will exec: python -m gplaydl auth --dispenser \"$DISPENSER\""
        python -m gplaydl auth --dispenser "$DISPENSER" 2>"$PLAYDL_STDERR" || true
    fi

     # Download base APK + splits
    if [[ -n "$DEVICE_PROFILE" ]]; then
        log_info "Will exec:  python -m gplaydl download \"$PACKAGE_NAME\" -o . --no-extras --no-splits --profile \"$DEVICE_PROFILE\""
        python -m gplaydl download "$PACKAGE_NAME" -o . --no-extras --no-splits --profile "$DEVICE_PROFILE" --dispenser "$DISPENSER" 2>"$PLAYDL_STDERR" 
    else
        log_info "Will exec:  python -m gplaydl download \"$PACKAGE_NAME\" -o . --no-extras --no-splits --dispenser \"$DISPENSER\"" 2>"$PLAYDL_STDERR" 
        python -m gplaydl download "$PACKAGE_NAME" -o . --no-extras --no-splits --dispenser "$DISPENSER" 2>"$PLAYDL_STDERR"
    fi
    APK_FILE=$(ls *.apk 2>/dev/null | head -1)
    # 4. Extract restrictions.xml
   if [[ ! -f "$APK_FILE" ]]; then
       cd -
       rm -rf "$TARGET_DIR"  # Clean up failed download directory
       log_error "Failed to download APK"
       END_EPOCH=$(date +%s)
       ELAPSED=$((END_EPOCH - START_EPOCH))
       echo "${START_DATE},${START_TIME},${CURRENT_VERSION},true,${ELAPSED},FAILURE (Failed to download APK)" >> "$LOG_FILE"
       exit 1
   fi
    IS_NEW=true
fi

cd "$START_DIR"
# 4. Extract if needed (skip if both XML files already exist)
#SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#echo "==== > $(pwd)  ...  <===="
EXTRACTED=false
if [[ ! -f "${TARGET_DIR}/app_restrictions.xml" ]] || [[ ! -f "${TARGET_DIR}/strings.xml" ]]; then
    log_info "Extracting restrictions from APK version ${CURRENT_VERSION}"
    bash extract_restrictions_from_last_apk.sh --subfolder "$SUBFOLDER" ${PACKAGE_NAME} 2>/dev/null
    EXTRACTED=true
else
    log_info "app_restrictions.xml and strings.xml already exist — skipping extraction"
fi

# 6. Consolidate if needed (skip if outputs already exist and weren't just extracted)
if [[ "$EXTRACTED" == "true" ]] || [[ ! -f "${TARGET_DIR}/app_restrictions_consolidated.csv" ]] || [[ ! -f "${TARGET_DIR}/app_restrictions_consolidated.json" ]]; then
    log_info "Consolidating restrictions to JSON/CSV"
    python3 "consolidate_restrictions.py" "${TARGET_DIR}"
else
    log_info "app_restrictions_consolidated.json and app_restrictions_consolidated.csv already exist — skipping consolidation"
fi

# Log success to CSV (separate from syslog-style logs)
END_EPOCH=$(date +%s)
ELAPSED=$((END_EPOCH - START_EPOCH))
echo "${START_DATE},${START_TIME},${CURRENT_VERSION},${IS_NEW},${ELAPSED},SUCCESS" >> "$LOG_FILE"

log_info "SUCCESS — outputs in ${TARGET_DIR}"
