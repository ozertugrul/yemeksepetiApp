#!/usr/bin/env bash
set -euo pipefail

# One-click flow on macOS:
#  1) rsync Linux repo -> mac local repo
#  2) run local sync_and_build_macos.sh with SKIP_SYNC=1

REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_HOST="${REMOTE_HOST:-127.0.0.1}"
REMOTE_PORT="${REMOTE_PORT:-2222}"
REMOTE_PATH="${REMOTE_PATH:-/root/ertu/yemeksepetiApp}"
LOCAL_ROOT="${LOCAL_ROOT:-/Users/ertu-mac/Desktop/yemeksepetiApp}"

SSH_OPTS="-p ${REMOTE_PORT} -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new"
RSYNC_SSH="ssh ${SSH_OPTS}"

if ! command -v rsync >/dev/null 2>&1; then
  echo "[ERROR] rsync not found on macOS. Install it first (brew install rsync)."
  exit 1
fi

if ! command -v ssh >/dev/null 2>&1; then
  echo "[ERROR] ssh not found on macOS."
  exit 1
fi

mkdir -p "${LOCAL_ROOT}"

echo "[A/3] Checking SSH connectivity..."
ssh ${SSH_OPTS} "${REMOTE_USER}@${REMOTE_HOST}" "echo connected" >/dev/null

echo "[B/3] Rsync Linux repo -> mac local repo..."
rsync -azv --delete --checksum --partial --exclude .git --exclude .build -e "${RSYNC_SSH}" \
  "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/" \
  "${LOCAL_ROOT}/"

echo "[C/3] Build + install on simulators..."
chmod +x "${LOCAL_ROOT}/scripts/sync_and_build_macos.sh"
SKIP_SYNC=1 bash "${LOCAL_ROOT}/scripts/sync_and_build_macos.sh"
