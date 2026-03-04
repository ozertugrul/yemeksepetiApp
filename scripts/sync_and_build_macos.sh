#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash scripts/sync_and_build_macos.sh
#
# Defaults are embedded for your setup:
#   REMOTE_USER=root
#   REMOTE_HOST=127.0.0.1
#   REMOTE_PORT=2222
#
# Optional override example:
#   REMOTE_USER=root REMOTE_HOST=127.0.0.1 REMOTE_PORT=2222 bash scripts/sync_and_build_macos.sh
#
# Optional env:
#   REMOTE_PATH=/root/ertu/yemeksepetiApp
#   LOCAL_ROOT=/Users/ertu-mac/Desktop/yemeksepetiApp
#   IOS_SIM='platform=iOS Simulator,name=iPhone 17 Pro'
#   AUTO_CLEAN=1

REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_HOST="${REMOTE_HOST:-127.0.0.1}"
REMOTE_PORT="${REMOTE_PORT:-2222}"
REMOTE_PATH="${REMOTE_PATH:-/root/ertu/yemeksepetiApp}"
LOCAL_ROOT="${LOCAL_ROOT:-/Users/ertu-mac/Desktop/yemeksepetiApp}"
IOS_SIM="${IOS_SIM:-platform=iOS Simulator,name=iPhone 17 Pro}"
SIMULATOR_NAMES="${SIMULATOR_NAMES:-iPhone 17 Pro,iPhone 12}"
SKIP_SYNC="${SKIP_SYNC:-0}"
AUTO_CLEAN="${AUTO_CLEAN:-1}"

SSH_OPTS="-p ${REMOTE_PORT} -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new"
RSYNC_SSH="ssh ${SSH_OPTS}"
RSYNC_COMMON_ARGS=(-az --delete --checksum --partial --exclude .git --exclude .build)
RSYNC_PROGRESS_ARGS=(--progress --stats)

if rsync --help 2>&1 | grep -q -- '--info'; then
  RSYNC_PROGRESS_ARGS=(--info=progress2,stats)
fi

if rsync --help 2>&1 | grep -q -- '--human-readable'; then
  RSYNC_COMMON_ARGS+=(--human-readable)
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "[ERROR] rsync not found on macOS. Install it first (brew install rsync)."
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "[ERROR] xcodebuild not found. Install Xcode + Command Line Tools."
  exit 1
fi

if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "[ERROR] xcodebuild is installed but not configured for full Xcode."
  echo "Run on macOS: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

if ! command -v ssh >/dev/null 2>&1; then
  echo "[ERROR] ssh not found on macOS."
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "[ERROR] xcrun not found on macOS."
  exit 1
fi

mkdir -p "${LOCAL_ROOT}"

echo "[0/4] Checking SSH connectivity (${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT})..."
if ! ssh ${SSH_OPTS} "${REMOTE_USER}@${REMOTE_HOST}" "echo connected" >/dev/null 2>&1; then
  echo "[ERROR] SSH connection failed: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}"
  echo "Make sure SSH tunnel/port-forward is active on macOS."
  exit 1
fi

REMOTE_HAS_RSYNC=0
if ssh ${SSH_OPTS} "${REMOTE_USER}@${REMOTE_HOST}" "command -v rsync >/dev/null 2>&1"; then
  REMOTE_HAS_RSYNC=1
fi

if ! ssh ${SSH_OPTS} "${REMOTE_USER}@${REMOTE_HOST}" "test -d '${REMOTE_PATH}'"; then
  echo "[ERROR] Remote path not found: ${REMOTE_PATH}"
  exit 1
fi

if [[ "${SKIP_SYNC}" != "1" ]]; then
  echo "[1/4] Dry-run compare (what will change)..."
  if [[ "${REMOTE_HAS_RSYNC}" -eq 1 ]]; then
    rsync "${RSYNC_COMMON_ARGS[@]}" "${RSYNC_PROGRESS_ARGS[@]}" -n -v -e "${RSYNC_SSH}" \
      "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/" \
      "${LOCAL_ROOT}/"
  else
    echo "[WARN] Remote rsync not found, dry-run diff skipped (fallback mode)."
  fi

  echo "[2/4] Syncing files from Linux repo to macOS local repo..."
  if [[ "${REMOTE_HAS_RSYNC}" -eq 1 ]]; then
    echo "[2/4] Running rsync with checksum overwrite..."
    rsync "${RSYNC_COMMON_ARGS[@]}" "${RSYNC_PROGRESS_ARGS[@]}" -v -e "${RSYNC_SSH}" \
      "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/" \
      "${LOCAL_ROOT}/"
  else
    TMP_SYNC_DIR="${LOCAL_ROOT%/}.tmp_sync"
    rm -rf "${TMP_SYNC_DIR}"
    mkdir -p "${TMP_SYNC_DIR}"
    echo "[2/4] Remote rsync yok, tar fallback ile senkron yapılıyor..."
    ssh ${SSH_OPTS} "${REMOTE_USER}@${REMOTE_HOST}" \
      "cd '${REMOTE_PATH}' && tar --exclude='.git' -cf - ." | tar -xf - -C "${TMP_SYNC_DIR}"
    rsync -a --delete --checksum --progress --stats "${TMP_SYNC_DIR}/" "${LOCAL_ROOT}/"
    rm -rf "${TMP_SYNC_DIR}"
  fi
else
  echo "[1/4] SKIP_SYNC=1 -> sync adımı atlandı"
fi

if [[ "${AUTO_CLEAN}" == "1" ]]; then
  echo "[3/6] Cleaning iOS build artifacts..."
  cd "${LOCAL_ROOT}"
  xcodebuild \
    -scheme yemeksepetiApp \
    -sdk iphonesimulator \
    -destination "${IOS_SIM}" \
    -derivedDataPath .build \
    clean
else
  echo "[3/6] AUTO_CLEAN=0 -> clean adımı atlandı"
fi

echo "[4/6] Building iOS app on simulator..."
cd "${LOCAL_ROOT}"
xcodebuild \
  -scheme yemeksepetiApp \
  -sdk iphonesimulator \
  -destination "${IOS_SIM}" \
  -derivedDataPath .build \
  build

APP_PATH="${LOCAL_ROOT}/.build/Build/Products/Debug-iphonesimulator/yemeksepetiApp.app"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "[ERROR] App bundle not found: ${APP_PATH}"
  exit 1
fi

APP_BUNDLE_ID="${APP_BUNDLE_ID:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP_PATH}/Info.plist" 2>/dev/null || true)}"
if [[ -z "${APP_BUNDLE_ID}" ]]; then
  echo "[ERROR] Could not determine CFBundleIdentifier from ${APP_PATH}/Info.plist"
  echo "Set APP_BUNDLE_ID manually and rerun."
  exit 1
fi

resolve_udid() {
  local sim_name="$1"
  xcrun simctl list devices available \
    | awk -v name="$sim_name" 'index($0, name " (") { print; exit }' \
    | grep -Eo '[A-Fa-f0-9-]{36}' \
    | head -n 1 || true
}

echo "[5/6] Installing and launching on simulators..."
IFS=',' read -r -a target_sims <<< "${SIMULATOR_NAMES}"
for sim_name_raw in "${target_sims[@]}"; do
  sim_name="$(echo "$sim_name_raw" | sed 's/^ *//; s/ *$//')"
  [[ -z "$sim_name" ]] && continue

  udid="$(resolve_udid "$sim_name")"
  if [[ -z "$udid" ]]; then
    echo "[WARN] Simulator not found: $sim_name"
    continue
  fi

  echo "  - $sim_name ($udid): boot/install/launch"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl uninstall "$udid" "$APP_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$udid" "$APP_PATH"
  xcrun simctl terminate "$udid" "$APP_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$udid" "$APP_BUNDLE_ID"
done

echo "[6/6] Build + install completed successfully."
echo "App bundle: ${APP_PATH}"
echo "Bundle ID: ${APP_BUNDLE_ID}"
