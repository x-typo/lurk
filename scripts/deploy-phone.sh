#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

load_env_local_defaults() {
    [[ -f .env.local ]] || return

    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        [[ "$line" == *=* ]] || continue

        key="${line%%=*}"
        value="${line#*=}"
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        [[ -z "${!key+x}" ]] || continue

        if [[ "$value" =~ ^\".*\"$ || "$value" =~ ^\'.*\'$ ]]; then
            value="${value:1:${#value}-2}"
        fi
        export "$key=$value"
    done < .env.local
}

load_env_local_defaults

PROJECT="${PROJECT:-Lurk.xcodeproj}"
SCHEME="${SCHEME:-Lurk}"
CONFIGURATION="${CONFIGURATION:-Debug}"
BUNDLE_ID="${BUNDLE_ID:-com.xtypo.Lurk}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/private/tmp/lurk-device-build}"
DEVICE_ID="${DEVICE_ID:-}"
DEVICE_NAME="${DEVICE_NAME:-}"
RESTART_COREDEVICE=0
LAUNCH_ONLY=0
SKIP_INSTALL=0
GENERIC_BUILD=0

usage() {
    cat <<USAGE
Usage: scripts/deploy-phone.sh [options]

Builds Lurk for a paired physical iPhone, installs it with devicectl, then launches it.

Options:
  --restart-coredevice   Restart CoreDeviceService before installing.
  --generic-build        Build for generic iOS, then install to the paired phone.
  --launch-only          Launch the installed app without building or installing.
  --skip-install         Build, then skip install and launch.
  -h, --help             Show this help.

Environment overrides:
  DEVICE_ID              Xcode destination/device identifier.
  DEVICE_NAME            Physical device name substring if multiple phones exist.
  CONFIGURATION          Build configuration. Default: Debug.
  DERIVED_DATA_PATH      Build output path. Default: /private/tmp/lurk-device-build.

The script also loads .env.local when present. This is the best place to keep
a personal DEVICE_ID because .env.local is ignored by git.
USAGE
}

log() {
    printf '\n==> %s\n' "$*"
}

warn() {
    printf '\nWARN: %s\n' "$*" >&2
}

die() {
    printf '\nERROR: %s\n' "$*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --restart-coredevice)
            RESTART_COREDEVICE=1
            shift
            ;;
        --generic-build)
            GENERIC_BUILD=1
            shift
            ;;
        --launch-only)
            LAUNCH_ONLY=1
            shift
            ;;
        --skip-install)
            SKIP_INSTALL=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

if [[ ! -d "$PROJECT" ]]; then
    die "Project not found: $PROJECT"
fi

resolve_device_id() {
    if [[ -n "$DEVICE_ID" ]]; then
        printf '%s\n' "$DEVICE_ID"
        return
    fi

    local destinations line resolved
    destinations="$(xcodebuild -showdestinations -project "$PROJECT" -scheme "$SCHEME" 2>&1 || true)"
    line="$(printf '%s\n' "$destinations" | awk -v device_name="$DEVICE_NAME" '
        index($0, "{ platform:iOS,") && index($0, "Simulator") == 0 && index($0, "placeholder") == 0 {
            if (device_name == "" || index($0, "name:" device_name) > 0) {
                print
                exit
            }
        }
    ')"

    if [[ -z "$line" ]]; then
        return 1
    fi

    resolved="$(printf '%s\n' "$line" | sed -nE 's/.*id:([^,}]+).*/\1/p' | xargs)"
    [[ -n "$resolved" ]] || return 1
    printf '%s\n' "$resolved"
}

resolve_coredevice_id() {
    if [[ -n "$DEVICE_ID" ]]; then
        printf '%s\n' "$DEVICE_ID"
        return
    fi

    local devices line resolved
    devices="$(xcrun devicectl list devices 2>&1 || true)"
    line="$(printf '%s\n' "$devices" | awk -v device_name="$DEVICE_NAME" '
        $0 ~ /iPhone/ && ($0 ~ /(^|[[:space:]])(available|connected)([[:space:]]|\\()/) {
            if (device_name == "" || index($0, device_name) > 0) {
                print
                exit
            }
        }
    ')"

    if [[ -z "$line" ]]; then
        printf '%s\n' "$devices" >&2
        die "No paired CoreDevice iPhone found. Set DEVICE_ID or DEVICE_NAME."
    fi

    resolved="$(printf '%s\n' "$line" | sed -nE 's/.*([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}).*/\1/p' | xargs)"
    [[ -n "$resolved" ]] || die "Could not parse CoreDevice id from: $line"
    printf '%s\n' "$resolved"
}

if [[ "$RESTART_COREDEVICE" == "1" ]]; then
    log "Restarting CoreDeviceService"
    killall CoreDeviceService 2>/dev/null || true
    sleep 2
fi

if [[ "$GENERIC_BUILD" == "1" ]]; then
    BUILD_DESTINATION="generic/platform=iOS"
    if [[ "$SKIP_INSTALL" == "1" ]]; then
        INSTALL_DEVICE_ID=""
    else
        INSTALL_DEVICE_ID="$(resolve_coredevice_id)"
    fi
elif DEVICE_ID="$(resolve_device_id)"; then
    BUILD_DESTINATION="id=$DEVICE_ID"
    INSTALL_DEVICE_ID="$DEVICE_ID"
else
    warn "Xcode did not report a paired physical iPhone destination."
    BUILD_DESTINATION="generic/platform=iOS"
    if [[ "$SKIP_INSTALL" == "1" ]]; then
        warn "Falling back to generic iOS device build."
        INSTALL_DEVICE_ID=""
    else
        warn "Falling back to generic iOS device build and CoreDevice install."
        DEVICE_ID="$(resolve_coredevice_id)"
        INSTALL_DEVICE_ID="$DEVICE_ID"
    fi
fi

APP_PATH="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphoneos/${SCHEME}.app"

if [[ -n "$INSTALL_DEVICE_ID" ]]; then
    log "Using device: $INSTALL_DEVICE_ID"
else
    log "Using generic iOS build destination"
fi

if [[ "$LAUNCH_ONLY" == "1" ]]; then
    if [[ -z "$INSTALL_DEVICE_ID" ]]; then
        INSTALL_DEVICE_ID="$(resolve_coredevice_id)"
    fi
    log "Launching $BUNDLE_ID"
    xcrun devicectl device process launch --device "$INSTALL_DEVICE_ID" "$BUNDLE_ID"
    exit 0
fi

log "Building $SCHEME ($CONFIGURATION)"
if ! xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$BUILD_DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build; then
    warn "Build failed before install."
    warn "If Xcode says the destination device cannot be found, unlock/replug the phone or open Xcode and Run once to refresh device services."
    exit 1
fi

[[ -d "$APP_PATH" ]] || die "Build succeeded, but app bundle was not found at $APP_PATH"

if [[ "$SKIP_INSTALL" == "1" ]]; then
    warn "Skipped install. Built app is at: $APP_PATH"
    exit 0
fi

log "Installing $APP_PATH"
if ! xcrun devicectl device install app --device "$INSTALL_DEVICE_ID" "$APP_PATH"; then
    warn "Direct install failed. This usually means CoreDeviceService is wedged, not that the app failed to build."
    warn "Retry with: scripts/deploy-phone.sh --restart-coredevice"
    warn "If it still fails, use Xcode: select your iPhone and press Run."
    exit 1
fi

log "Launching $BUNDLE_ID"
xcrun devicectl device process launch --device "$INSTALL_DEVICE_ID" "$BUNDLE_ID"
