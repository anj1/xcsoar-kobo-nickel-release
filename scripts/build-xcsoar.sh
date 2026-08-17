#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

if [ -n "${XCSOAR_DIR:-}" ]; then
  XCSOAR_DIR=$(CDPATH= cd -- "$XCSOAR_DIR" && pwd)
else
  XCSOAR_DIR=$(CDPATH= cd -- "$APP_DIR/../XCSoar" && pwd)
fi

if [ ! -f "$XCSOAR_DIR/Makefile" ] || [ ! -d "$XCSOAR_DIR/.git" ]; then
  echo "XCSOAR_DIR must point to a complete XCSoar git checkout: $XCSOAR_DIR" >&2
  exit 1
fi

IMAGE=${IMAGE:-nickeltc-gcc14}
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}

echo "Building XCSoar $(git -C "$XCSOAR_DIR" rev-parse --short HEAD) with $IMAGE"
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -v "$XCSOAR_DIR:/work" \
  -w /work \
  "$IMAGE" \
  make -j"$JOBS" TARGET=KOBO_NICKEL DEBUG=n WERROR=y
