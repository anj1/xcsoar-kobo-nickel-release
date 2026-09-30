#!/bin/sh
set -eu

DIST_DIR="${KOBO_PACKAGE_DIR:?Set KOBO_PACKAGE_DIR to the unpacked release directory}"

HOST="${KOBO_HOST:?Set KOBO_HOST to the Kobo SSH target, for example root@kobo.local}"
REMOTE_DIR="${KOBO_XCSOAR_DIR:-/mnt/onboard/.adds/xcsoar}"
LOG="$REMOTE_DIR/logs/xcsoar.log"

case "$REMOTE_DIR" in
  /*) ;;
  *) echo "KOBO_XCSOAR_DIR must be an absolute device path" >&2; exit 1 ;;
esac
case "$REMOTE_DIR" in
  *[!a-zA-Z0-9_./-]*) echo "Unsupported characters in KOBO_XCSOAR_DIR" >&2; exit 1 ;;
esac

if [ ! -x "$DIST_DIR/xcsoar" ]; then
  echo "Missing $DIST_DIR/xcsoar; run scripts/package-xcsoar.sh first." >&2
  exit 1
fi

# Let the currently installed supervisor finish using its matching stop script
# before updating any of the payload. Keep existing data, profiles, and logs.
ssh "$HOST" "
  set -eu
  if [ -x '$REMOTE_DIR/stop.sh' ]; then '$REMOTE_DIR/stop.sh'; fi
"

tar -C "$DIST_DIR" -cf - . | ssh "$HOST" "
  set -eu
  mkdir -p '$REMOTE_DIR'
  tar -C '$REMOTE_DIR' -xf -
  chmod +x '$REMOTE_DIR/xcsoar' '$REMOTE_DIR/run.sh' '$REMOTE_DIR/stop.sh'
"

ssh "$HOST" "
  set -eu
  '$REMOTE_DIR/run.sh'
  sleep \${KOBO_XCSOAR_WAIT:-8}
  cat '$LOG' 2>/dev/null || true
"
