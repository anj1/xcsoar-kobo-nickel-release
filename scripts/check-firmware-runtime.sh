#!/bin/sh
set -eu

[ "$#" = 2 ] || {
  echo "usage: $0 EXTRACTED_FIRMWARE_ROOT PACKAGE_DIR" >&2
  exit 2
}
FIRMWARE_ROOT=$(CDPATH= cd -- "$1" && pwd)
PACKAGE_DIR=$(CDPATH= cd -- "$2" && pwd)
IMAGE=${IMAGE:-nickeltc-gcc14}
[ -f "$FIRMWARE_ROOT/lib/libc.so.6" ]
[ -f "$FIRMWARE_ROOT/lib/ld-linux-armhf.so.3" ]
[ -x "$PACKAGE_DIR/xcsoar" ]
[ -f "$PACKAGE_DIR/lib/libfbink.so.1" ]

readelf -lW "$PACKAGE_DIR/xcsoar"
readelf -dW "$PACKAGE_DIR/xcsoar"
readelf -VW "$PACKAGE_DIR/xcsoar"
readelf -dW "$PACKAGE_DIR/lib/libfbink.so.1.0.0"
readelf -VW "$PACKAGE_DIR/lib/libfbink.so.1.0.0"

# Firmware code only runs in this disposable container, with read-only inputs,
# no network, and no Kobo framebuffer/input/UART devices passed through.
docker run --rm --network none --cap-drop ALL \
  --security-opt no-new-privileges --user "$(id -u):$(id -g)" \
  -v "$FIRMWARE_ROOT:/firmware:ro" -v "$PACKAGE_DIR:/package:ro" \
  "$IMAGE" sh -eu -c '
    qemu-arm -L /firmware /firmware/lib/ld-linux-armhf.so.3 \
      --library-path /package/lib:/firmware/lib:/firmware/usr/lib \
      --list /package/xcsoar
    qemu-arm -L /firmware -E LD_BIND_NOW=1 \
      /firmware/lib/ld-linux-armhf.so.3 \
      --library-path /package/lib:/firmware/lib:/firmware/usr/lib \
      /package/xcsoar --version
    # Exercise the final application-relative RUNPATH, with no launcher or
    # explicit library-path override, as well as the firmware loader check.
    qemu-arm -L /firmware -U LD_LIBRARY_PATH -E LD_BIND_NOW=1 \
      /package/xcsoar --version
  '
