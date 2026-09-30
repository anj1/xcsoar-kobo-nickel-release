# XCSoar for Kobo Clara Colour

This repository builds and packages XCSoar's `KOBO_NICKEL` target, installed
under `/mnt/onboard/.adds/xcsoar/` and launched by NickelMenu. XCSoar uses the
framebuffer and FBInk; it does not link Qt or Nickel's private ABI. Qt6
firmware therefore needs platform discovery and launcher changes, not a Qt6
rewrite of XCSoar.

The source checkout is [anj1/XCSoar](https://github.com/anj1/XCSoar), branch
`kobo-nickel-compat`. This branch adds firmware compatibility changes without
updating the source branch of pending upstream PR #2865. The build uses GCC 14.3.0 from
[anj1/NickelTC](https://github.com/anj1/NickelTC), with matched static C++
runtimes and the existing FBInk pin. It uses the firmware's libc and loader.

## Installation

A NickelMenu build compatible with the device's **exact firmware** must
already be installed. Firmware 5.x/6.x using Qt6 requires a Qt6-compatible
NickelMenu, such as the owner's port. This package does not supply that plugin
or claim that a compatible public release is available. Older Qt5 NickelMenu
installation instructions do not apply to Qt6 firmware.

Download an archive from the [releases page](https://github.com/anj1/xcsoar-kobo-nickel-release/releases),
verify its checksum, and copy its contents into:

```text
/mnt/onboard/.adds/xcsoar/
```

Keep the executable, `lib/`, `fonts/`, `run.sh`, `stop.sh`,
`xcsoar-common.sh`, and `default-kobo-gnss.prf` together. Preserve existing
`XCSoarData` and profiles. Do not install XCSoar's legacy `KoboRoot.tgz` or
replace Kobo's boot flow.

Add these entries to `.adds/nm/config`:

```ini
menu_item :main :XCSoar :cmd_spawn :quiet:/mnt/onboard/.adds/xcsoar/run.sh
menu_item :main :Stop XCSoar :cmd_spawn :quiet:/mnt/onboard/.adds/xcsoar/stop.sh
```

Eject the device before launching. Start with simulation/static data and
confirm display and touch before testing GNSS.

## Runtime configuration

The default GNSS configuration is the owner's existing `/dev/ttyS0`, 9600
baud, Generic driver. First launch installs the packaged profile only when
`/mnt/onboard/XCSoarData/default.prf` is absent. `GNSS_SERIAL_PORT` selects the
UART and is also written into a newly installed profile. With an existing
profile, its `PortPath` must match that setting; mismatches fail with a
diagnostic instead of overwriting user configuration. Confirm receiver wiring
and baud rate on the actual device. UART lifecycle management covers this
selected port; additional ports or alternate profiles need corresponding
configuration and validation.

For a run which does not acquire a UART, use:

```sh
XCSOAR_GNSS=off /mnt/onboard/.adds/xcsoar/run.sh
```

This forces XCSoar's simulator mode and leaves the GNSS profile intact. A
NickelMenu simulation entry can use the same environment assignment after
`quiet:`. `XCSOAR_ARGS` is an optional whitespace-separated argument list.

Touch discovery honors a nonempty `KOBO_TOUCH_DEVICE` first, then checks
`/dev/input/touchscreen`, `touchscreen0`, `tablet`, and numerically ordered
event devices. Supported protocols include legacy coordinates with
`BTN_TOUCH`, type-A multitouch coordinates with `BTN_TOUCH`, and type-B
multitouch slots with tracking IDs. Every candidate must provide supported
touch capabilities; pen-only and accelerometer devices are rejected. Direct
multitouch devices may also advertise pen support, as `cyttsp5_mt` does.
An invalid override or failed touch grab causes startup to exit.
Power input is discovered by `KEY_POWER`;
`KOBO_POWER_DEVICE` is an optional explicit override. The same device cannot
be opened for both roles. Logs record each candidate's name and capabilities,
and the selected input protocol and axis ranges; Kobo's existing coordinate
and rotation mapping is retained pending
screen-alignment checks on hardware.

The supervisor records PID plus start time for its child and each process it
suspends. It preserves processes already stopped before launch. State lives
in `/tmp/xcsoar.session`; firmware's `flock` serializes modern launches, with
a directory-lock fallback for older firmware. It suspends only active
`sickel`, `fontickel`, and `nickel` processes; device validation must confirm
those processes cover the active watchdogs. It leaves `mdpd` alone.

If no serial owner exists, no getty manipulation is performed. `getty`/`agetty`
directly supervised by Qt6 firmware's `start_getty` or the legacy
`kobo_getty.sh` can be released after suspending that wrapper. The wrapper
waits for its foreground child, so suspending it prevents exit and init
respawn during UART takeover. On cleanup, termios is restored before the
wrapper resumes; init can then respawn its console normally. Other UART
owners, including an interactive login or an unidentified supervisor, cause
a useful error. The launcher never terminates arbitrary UART owners.

Cleanup terminates and waits for XCSoar, restores the saved UART's termios,
resumes the recorded serial wrapper, and resumes the recorded Nickel
processes. Failed UART restoration retains its recovery state. Normal stop,
crash recovery, repeated stop, and stale sessions use shared cleanup code.

Nickel's menu is inaccessible while Nickel is suspended: exit from XCSoar's
own menu, or use `stop.sh` over SSH. Logs are in `.adds/xcsoar/logs/xcsoar.log`.
Suspend, USB mounting/eject, and firmware updates during XCSoar ownership have
not been validated; exit XCSoar before those operations.

## Local build and verification

Requirements: the GCC14 Docker image, Git, binutils (`strings`, `readelf`),
`zip`, `sha256sum`, and DejaVu Sans fonts. Place this repository beside XCSoar
or set `XCSOAR_DIR` explicitly:

```sh
XCSOAR_DIR=/path/to/XCSoar IMAGE=nickeltc-gcc14 ./scripts/build-xcsoar.sh
XCSOAR_DIR=/path/to/XCSoar IMAGE=nickeltc-gcc14 \
  RELEASE_VERSION=qt6-test ./scripts/package-xcsoar.sh
python3 -m unittest discover -s tests -v
```

Build uses `TARGET=KOBO_NICKEL DEBUG=n WERROR=y`. Packaging compares the source
fingerprint with the build, rejects unexpected dynamic C++ runtimes or GLIBC
imports newer than 2.19, and includes source patches, compiler/image
information, and payload hashes. It creates a versioned directory and ZIP in
`dist/` without clearing previous output. Choose a new version or `OUTPUT_DIR`
if that version already exists. The executable uses `$ORIGIN/lib` RUNPATH and
the launcher puts the bundled FBInk first in `LD_LIBRARY_PATH`; no Qt SDK
search paths or SDK libc/loader are installed.

Build ARM regressions with `make TARGET=KOBO_NICKEL DEBUG=n WERROR=y
output/KOBO_NICKEL/bin/TestKoboModel output/KOBO_NICKEL/bin/TestKoboInput` inside
the image. Run them using `qemu-arm` and the extracted target firmware loader,
with the package's FBInk directory in the loader's library path. Launcher
tests use disposable processes and PTYs and replace `pidof` with a fixture;
they do not address real Nickel processes.

After verifying and extracting an official firmware archive, check linkage
and early startup in an isolated container:

```sh
./scripts/check-firmware-runtime.sh /path/to/extracted-rootfs /path/to/package
```

Inputs are mounted read-only, networking is disabled, and no physical device
nodes are passed through. The check also runs `--version` with no library-path
override to exercise the final RUNPATH. It cannot validate UI or hardware.

## Firmware evidence

| Firmware | Offline evidence for this migration | Physical-device evidence |
| --- | --- | --- |
| 4.x | Legacy model source and input policy retained; not rerun against a 4.x rootfs | Owner's earlier build worked; this revision untested |
| 5.18.270971 | Targeted by the implementation; rootfs execution pending | Pending |
| 6.0.274403 | GCC14 build and ARM model/input regressions passed; package runtime checks recorded in `validation-qt6.md` | Owner reports working on Clara Colour; full hardware checklist pending |

The 6.0.274403 archive used for checks has SHA-256
`31d1462b3c7ae9f850c04b752b654404407cc4605c50885318a876ddb3b9ce47`.
Do not infer all firmware 5.x/6.x support from one offline check. Hardware
acceptance still needs N367/300 DPI/colour defaults/`wlan0`, touch corners,
drags/releases/rotations and return to Nickel, framebuffer refreshes, actual
NMEA reception, watchdog stability, Wi-Fi control, repeated launches, and
post-exit suspend/USB/cold-boot checks.

## Releases

Tags matching `vX.Y.Z` build and publish a release using the configured source
branch and NickelTC image. The archive contains the application payload and
build provenance, not a Qt SDK or NickelMenu. Select an explicit source
revision/image for reproducible releases. The optional SSH helper accepts
`KOBO_HOST` and deploys a selected package directory via `KOBO_PACKAGE_DIR`.

## License

XCSoar is distributed under the GNU General Public License. See
[LICENSE](LICENSE) and XCSoar's third-party notices.
