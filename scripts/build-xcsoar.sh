#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

if [ -n "${XCSOAR_DIR:-}" ]; then
  XCSOAR_DIR=$(CDPATH= cd -- "$XCSOAR_DIR" && pwd)
else
  XCSOAR_DIR=$(CDPATH= cd -- "$APP_DIR/../XCSoar" && pwd)
fi

if [ ! -f "$XCSOAR_DIR/Makefile" ] ||
   ! git -C "$XCSOAR_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "XCSOAR_DIR must point to a complete XCSoar git checkout: $XCSOAR_DIR" >&2
  exit 1
fi

IMAGE=${IMAGE:-nickeltc-gcc14}
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}

. "$SCRIPT_DIR/source-manifest.sh"

MANIFEST=$(mktemp)
AFTER_MANIFEST=$(mktemp)
trap 'rm -f "$MANIFEST" "$AFTER_MANIFEST"' EXIT
source_manifest "$XCSOAR_DIR" > "$MANIFEST"

echo "Building XCSoar $(git -C "$XCSOAR_DIR" rev-parse --short HEAD) with $IMAGE"
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -v "$XCSOAR_DIR:/work" \
  -w /work \
  "$IMAGE" \
  make -j"$JOBS" TARGET=KOBO_NICKEL DEBUG=n WERROR=y

source_manifest "$XCSOAR_DIR" > "$AFTER_MANIFEST"
cmp -s "$MANIFEST" "$AFTER_MANIFEST" || {
  echo "XCSoar sources changed during the build; rebuild before packaging." >&2
  exit 1
}
cp "$MANIFEST" "$XCSOAR_DIR/output/KOBO_NICKEL/source-manifest.sha256"
{
  docker run --rm --network none "$IMAGE" arm-nickel-linux-gnueabihf-g++ --version
  echo "Image identity: $(docker image inspect --format '{{.Id}} {{json .RepoDigests}}' "$IMAGE")"
} > "$XCSOAR_DIR/output/KOBO_NICKEL/build-toolchain.txt"
