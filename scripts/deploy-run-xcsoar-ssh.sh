#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$APP_DIR/dist-xcsoar"

HOST="${KOBO_HOST:?Set KOBO_HOST to the Kobo SSH target, for example root@kobo.local}"
REMOTE_DIR="${KOBO_XCSOAR_DIR:-/mnt/onboard/.adds/xcsoar}"
LOG="$REMOTE_DIR/logs/xcsoar.log"

if [ ! -x "$DIST_DIR/xcsoar" ]; then
  echo "Missing $DIST_DIR/xcsoar; run scripts/package-xcsoar.sh first." >&2
  exit 1
fi

tar -C "$DIST_DIR" -cf - . | ssh "$HOST" "
  set -eu
  mkdir -p '$REMOTE_DIR'
  tar -C '$REMOTE_DIR' -xf -
  chmod +x '$REMOTE_DIR/xcsoar' '$REMOTE_DIR/run.sh' '$REMOTE_DIR/stop.sh'
"

ssh "$HOST" "
  set -eu
  '$REMOTE_DIR/stop.sh' || true
  rm -f '$LOG'
  '$REMOTE_DIR/run.sh'
  sleep \${KOBO_XCSOAR_WAIT:-8}
  cat '$LOG' 2>/dev/null || true
"
