#!/bin/bash
# extract_restrictions_from_last_apk.sh
# Usage: bash extract_restrictions_from_last_apk.sh [--subfolder <dir>] <package-name>
#   e.g: bash extract_restrictions_from_last_apk.sh com.microsoft.emmx
#   e.g: bash extract_restrictions_from_last_apk.sh --subfolder my-downloads com.microsoft.emmx

# ── Syslog-style logging ──────────────────────────────────────────────
SCRIPT_NAME="$(basename "$0")"

_syslog() {
    local level="$1"
    shift
    local msg="$*"
    local ts
    ts="$(date '+%b %d %H:%M:%S')"
    local line="${ts} $(hostname) ${SCRIPT_NAME}[$$]: ${level}: ${msg}"
    echo "$line"
    { echo "$line" >> "$LOG_FILE"; } 2>/dev/null || true
}

log_info()   { _syslog "INFO"   "$@"; }
log_warn()   { _syslog "WARN"   "$@"; }
log_error() { _syslog "ERROR" "$@"; }
die() {
    log_error "$@"
    rm -rf /tmp/decoded
    exit 1
}
# ───────────────────────────────────────────────────────────────────────

# Validate argument
PACKAGE_NAME=""
SUBFOLDER="Playstore-Downloads"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --subfolder)
            if [[ -z "${2:-}" ]]; then
                log_error "--subfolder requires a value."
                log_error "Usage: bash $(basename "$0") --subfolder <dir> <package-name>"
                exit 1
            fi
            SUBFOLDER="$2"
            shift 2
            ;;
        *)
            if [[ -z "$PACKAGE_NAME" ]]; then
                PACKAGE_NAME="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$PACKAGE_NAME" ]]; then
    log_error "Usage: bash $(basename "$0") --subfolder <dir> <package-name>"
    exit 1
fi

mkdir -p "$SUBFOLDER"
LOG_FILE="$SUBFOLDER/extract.log"

log_info "Starting extraction for package: ${PACKAGE_NAME}"

# 1. Detect OS and set the preferred command
if [[ "$OSTYPE" == "darwin"* ]]; then
    # ggrep is an alias to grep with GNU extensions on macOS (installed via Homebrew)
    GREP_CMD="ggrep"
else
    GREP_CMD="grep"
fi

# 2. Check if the command exists in PATH
if ! command -v "$GREP_CMD" &> /dev/null; then
    log_error "'$GREP_CMD' not found."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        log_error "Please install GNU grep on macOS using: brew install grep"
    else
        log_error "Please install GNU grep on your Linux distribution (e.g., sudo apt install grep)"
    fi
    exit 1
fi

# 3. Execute the search

# Capture script directory early (before any cd changes cwd)
SCRIPT_DIR="$(pwd)"

BASE_DIR="$SUBFOLDER"

cd "$BASE_DIR"

# Update LOG_FILE to absolute path after cd
LOG_FILE="${SCRIPT_DIR}/$SUBFOLDER/extract.log"
# Find the latest downloaded version directory
# the below works like a charm for mac I need to propose a solution for linux as well
#LATEST_DIR=$(find . -mindepth 1 -maxdepth 1 -type d -exec stat -f "%B %N" {} + | sort -rn | head -n 1 | cut -d' ' -f2-)
LATEST_DIR=$(ls -d "${PACKAGE_NAME}"* | sort -V | tail -n 1)


APK_DIR="$(pwd)/$LATEST_DIR"
log_info "Latest downloaded APK directory: ${APK_DIR}"

cd "$APK_DIR"

# Idempotency: skip extraction if outputs already exist
if [[ -f "$APK_DIR/app_restrictions.xml" ]] && [[ -f "$APK_DIR/strings.xml" ]]; then
    log_info "app_restrictions.xml and strings.xml already exist in ${APK_DIR} — skipping extraction"
    log_info "SUCCESS — extraction skipped (already up to date)"
    exit 0
fi

# Extract base APK
APK_FILE=$(ls *.apk 2>/dev/null | head -1)
if [[ -z "$APK_FILE" ]]; then
    log_error "No APK file found in ${APK_DIR}"
    exit 1
fi
log_info "Found APK file: ${APK_FILE}"

cd /tmp
# extract file in apk under /tmp/decoded/
apktool d "$APK_DIR/$APK_FILE" -o decoded --no-src 2>/dev/null
cd decoded

# search for the common file that contains this string '<restrictions\s+xmlns:android="http://schemas.android.com/apk/res/android">' 
# it will be the one holding the restrictions that can be managed via MDM.
# there is high probability that the file is under res/xml/ or res/values/ folder
# Note: -l lists files, -P enables Perl regex, -z handles null bytes/newlines, -o outputs match
# We search in the current directory (.)
log_info "Searching for restrictions tag..."


# Find the file that contains ALL 3 strings (the MDM restrictions file)
#RESTRICTIONS_FILE=$(grep -rlE "HomepageLocation" ./ | xargs grep -l "ScreenCaptureAllowedByOrigins" | xargs grep -l "CopilotNewTabPageEnabled" | head -1)
RESTRICTIONS_FILE=$($GREP_CMD -rlPzo '<restrictions\s+xmlns:android="http://schemas.android.com/apk/res/android">');

if [ -z "$RESTRICTIONS_FILE" ]; then
    die "Could not find a file containing restrictions."
    exit 1;
fi

# Resolve to absolute path before changing directory
RESTRICTIONS_FILE="$(cd "$(dirname "$RESTRICTIONS_FILE")" && pwd)/$(basename "$RESTRICTIONS_FILE")"

# Copy RESTRICTIONS_FILE to APK_DIR for later use
cp "$RESTRICTIONS_FILE" "$APK_DIR/"

# Copy to app_restrictions.xml
cp "$RESTRICTIONS_FILE" "$APK_DIR/app_restrictions.xml"

# Find strings.xml and copy to APK_DIR (only if it doesn't already exist)
# From experience, the strings.xml file is always in res/values/ folder, so we can directly look for it there
STRINGS_FILE=$(find ./res/values -name "strings.xml" | head -1)
if [ -n "$STRINGS_FILE" ]; then
    cp "$STRINGS_FILE" "$APK_DIR/"
else
    log_warn "strings.xml not found in expected location (res/values/) — using fallback method"
    STRINGS_FILE=$(find ./ -name "strings.xml" | head -1)
fi

# CD $APK_DIR
cd "$APK_DIR"


# Cleanup
rm -rf /tmp/decoded

# Show file path to user
log_info "MDM restrictions file: ${APK_DIR}/app_restrictions.xml"
log_info "SUCCESS — extraction complete"
