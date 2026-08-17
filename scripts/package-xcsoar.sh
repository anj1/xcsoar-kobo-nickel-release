#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

if [ -n "${XCSOAR_DIR:-}" ]; then
  XCSOAR_DIR=$(CDPATH= cd -- "$XCSOAR_DIR" && pwd)
else
  XCSOAR_DIR=$(CDPATH= cd -- "$APP_DIR/../XCSoar" && pwd)
fi

IMAGE=${IMAGE:-nickeltc-gcc14}
VERSION=${RELEASE_VERSION:-$(sed -n 's/[[:space:]]//gp' "$XCSOAR_DIR/VERSION.txt")}
VERSION=$(printf '%s' "$VERSION" | tr '/ ' '__')
DIST_DIR=${OUTPUT_DIR:-"$APP_DIR/dist"}
PACKAGE_DIR="$DIST_DIR/xcsoar-kobo-clara-colour-$VERSION"
ARCHIVE="$DIST_DIR/xcsoar-kobo-clara-colour-$VERSION.zip"
BIN="$XCSOAR_DIR/output/KOBO_NICKEL/bin/xcsoar"
SYSROOT=/tc/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot

for command in git strings zip sha256sum; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

[ -x "$BIN" ] || {
  echo "Missing XCSoar binary: $BIN" >&2
  echo "Run scripts/build-xcsoar.sh first." >&2
  exit 1
}

EXPECTED_COMMIT=$(git -C "$XCSOAR_DIR" rev-parse --short HEAD)
EMBEDDED_COMMIT=$(strings "$BIN" | sed -n 's/.*~git#//p' | head -n 1)
[ "$EMBEDDED_COMMIT" = "$EXPECTED_COMMIT" ] || {
  echo "XCSoar binary revision mismatch (binary=$EMBEDDED_COMMIT checkout=$EXPECTED_COMMIT)" >&2
  echo "Run scripts/build-xcsoar.sh before packaging." >&2
  exit 1
}

FONT_SOURCE_DIR=${FONT_SOURCE_DIR:-}
if [ -z "$FONT_SOURCE_DIR" ]; then
  for candidate in /usr/share/fonts/truetype/dejavu /usr/share/fonts/dejavu; do
    if [ -f "$candidate/DejaVuSansCondensed.ttf" ]; then
      FONT_SOURCE_DIR=$candidate
      break
    fi
  done
fi
[ -f "$FONT_SOURCE_DIR/DejaVuSansCondensed.ttf" ] || {
  echo "DejaVu fonts not found; set FONT_SOURCE_DIR to their directory." >&2
  exit 1
}

rm -rf "$DIST_DIR"
mkdir -p "$PACKAGE_DIR/lib" "$PACKAGE_DIR/fonts"
cp "$BIN" "$PACKAGE_DIR/xcsoar"
cp "$APP_DIR/scripts/xcsoar-run.sh" "$PACKAGE_DIR/run.sh"
cp "$APP_DIR/scripts/xcsoar-stop.sh" "$PACKAGE_DIR/stop.sh"
cp "$APP_DIR/default-kobo-gnss.prf" "$PACKAGE_DIR/default-kobo-gnss.prf"

if [ -n "${FBINK_LIB_DIR:-}" ]; then
  cp "$FBINK_LIB_DIR"/libfbink.so* "$PACKAGE_DIR/lib/"
else
  docker run --rm "$IMAGE" tar -C "$SYSROOT/usr/lib" -cf - \
    libfbink.so libfbink.so.1 libfbink.so.1.0.0 |
    tar -x -C "$PACKAGE_DIR/lib"
fi

for font in \
  DejaVuSansCondensed.ttf DejaVuSansCondensed-Bold.ttf \
  DejaVuSansCondensed-Oblique.ttf DejaVuSansCondensed-BoldOblique.ttf \
  DejaVuSansMono.ttf DejaVuSansMono-Bold.ttf \
  DejaVuSansMono-Oblique.ttf DejaVuSansMono-BoldOblique.ttf
do
  [ -f "$FONT_SOURCE_DIR/$font" ] && cp "$FONT_SOURCE_DIR/$font" "$PACKAGE_DIR/fonts/$font"
done

chmod 0755 "$PACKAGE_DIR/xcsoar" "$PACKAGE_DIR/run.sh" "$PACKAGE_DIR/stop.sh"
{
  echo "XCSoar Kobo Clara Colour release $VERSION"
  echo "XCSoar commit: $(git -C "$XCSOAR_DIR" rev-parse HEAD)"
  echo "NickelTC image: $IMAGE"
  echo "Built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$PACKAGE_DIR/build-info.txt"

(cd "$PACKAGE_DIR" && zip -qr "$ARCHIVE" .)
sha256sum "$ARCHIVE" > "$ARCHIVE.sha256"
echo "Created $ARCHIVE"
