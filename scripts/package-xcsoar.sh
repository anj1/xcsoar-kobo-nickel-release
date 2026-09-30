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
[ -n "$VERSION" ] && [ "$VERSION" != . ] && [ "$VERSION" != .. ] || {
  echo "Release version must be nonempty and valid; set RELEASE_VERSION." >&2
  exit 1
}
DIST_DIR=${OUTPUT_DIR:-"$APP_DIR/dist"}
mkdir -p "$DIST_DIR"
# ZIP creation runs from PACKAGE_DIR; resolve relative output paths first.
DIST_DIR=$(CDPATH= cd -- "$DIST_DIR" && pwd)
PACKAGE_DIR="$DIST_DIR/xcsoar-kobo-clara-colour-$VERSION"
ARCHIVE="$DIST_DIR/xcsoar-kobo-clara-colour-$VERSION.zip"
BIN="$XCSOAR_DIR/output/KOBO_NICKEL/bin/xcsoar"
SYSROOT=/tc/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot

for command in git strings zip sha256sum readelf cmp; do
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

# A matching HEAD is insufficient for an uncommitted migration build.
MANIFEST=$(mktemp)
trap 'rm -f "$MANIFEST"' EXIT
. "$SCRIPT_DIR/source-manifest.sh"
source_manifest "$XCSOAR_DIR" > "$MANIFEST"
cmp -s "$MANIFEST" "$XCSOAR_DIR/output/KOBO_NICKEL/source-manifest.sha256" || {
  echo "Binary/source snapshot mismatch; run scripts/build-xcsoar.sh before packaging." >&2
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

if [ -e "$PACKAGE_DIR" ] || [ -e "$ARCHIVE" ]; then
  echo "Release output already exists; choose a new RELEASE_VERSION or OUTPUT_DIR." >&2
  exit 1
fi
mkdir -p "$PACKAGE_DIR/lib" "$PACKAGE_DIR/fonts"
cp "$BIN" "$PACKAGE_DIR/xcsoar"
cp "$APP_DIR/scripts/xcsoar-run.sh" "$PACKAGE_DIR/run.sh"
cp "$APP_DIR/scripts/xcsoar-stop.sh" "$PACKAGE_DIR/stop.sh"
cp "$APP_DIR/scripts/xcsoar-common.sh" "$PACKAGE_DIR/xcsoar-common.sh"
cp "$APP_DIR/default-kobo-gnss.prf" "$PACKAGE_DIR/default-kobo-gnss.prf"

if [ -n "${FBINK_LIB_DIR:-}" ]; then
  cp "$FBINK_LIB_DIR"/libfbink.so* "$PACKAGE_DIR/lib/"
else
  docker run --rm "$IMAGE" tar -C "$SYSROOT/usr/lib" -cf - \
    libfbink.so libfbink.so.1 libfbink.so.1.0.0 |
    tar -x -C "$PACKAGE_DIR/lib"
fi

# Audit the bundled library as well as the executable.
for binary in "$PACKAGE_DIR/xcsoar" "$PACKAGE_DIR/lib/libfbink.so.1.0.0"; do
  versions=$(readelf -VW "$binary")
  if printf '%s\n' "$versions" | grep -Eq 'GLIBCXX_|CXXABI_' ||
     readelf -dW "$binary" | grep -Eq 'Shared library: \[(libstdc\+\+|libgcc_s)'; then
    echo "Unexpected dynamic C++ runtime in $binary" >&2
    exit 1
  fi
  bad_glibc=$(printf '%s\n' "$versions" |
    sed -n 's/.*Name: GLIBC_\([0-9][0-9.]*\).*/\1/p' |
    awk -F. '$1 > 2 || ($1 == 2 && $2 > 19) { print }')
  [ -z "$bad_glibc" ] || {
    echo "Unsupported glibc versions in $binary: $bad_glibc" >&2
    exit 1
  }
done

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
  echo "XCSoar branch: $(git -C "$XCSOAR_DIR" branch --show-current)"
  echo "XCSoar local changes: $(git -C "$XCSOAR_DIR" status --porcelain | wc -l)"
  echo "NickelTC image: $IMAGE"
  echo "NickelTC image identity: $(docker image inspect --format '{{.Id}} {{json .RepoDigests}}' "$IMAGE")"
  echo "FBInk revision: 886f25f13368859ad8a899b88d04c26e19cda32e (NickelTC pin; verify for custom FBINK_LIB_DIR)"
  echo "Built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$PACKAGE_DIR/build-info.txt"
git -C "$XCSOAR_DIR" diff HEAD > "$PACKAGE_DIR/xcsoar-local.patch"
git -C "$APP_DIR" diff HEAD > "$PACKAGE_DIR/launcher-local.patch"
# Include new source files too: ordinary git diff omits untracked files.
for repository in "$XCSOAR_DIR" "$APP_DIR"; do
  if [ "$repository" = "$XCSOAR_DIR" ]; then
    patch="$PACKAGE_DIR/xcsoar-local.patch"
  else
    patch="$PACKAGE_DIR/launcher-local.patch"
  fi
  git -C "$repository" ls-files --others --exclude-standard |
    while IFS= read -r file; do
      git -C "$repository" diff --no-index -- /dev/null "$file" >> "$patch" ||
        [ "$?" -eq 1 ]
    done
done
cp "$MANIFEST" "$PACKAGE_DIR/source-manifest.sha256"
if [ -f "$XCSOAR_DIR/output/KOBO_NICKEL/build-toolchain.txt" ]; then
  cp "$XCSOAR_DIR/output/KOBO_NICKEL/build-toolchain.txt" "$PACKAGE_DIR/"
fi
(cd "$PACKAGE_DIR" && sha256sum xcsoar lib/libfbink.so.1.0.0 run.sh stop.sh xcsoar-common.sh > payload.sha256)

(cd "$PACKAGE_DIR" && zip -qr "$ARCHIVE" .)
sha256sum "$ARCHIVE" > "$ARCHIVE.sha256"
echo "Created $ARCHIVE"
