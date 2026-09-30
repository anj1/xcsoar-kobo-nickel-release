# Qt6 firmware migration validation — 2026-09-30

The owner reports the migration working on their Clara Colour running
firmware **6.x**, after installing the cyttsp5 fix described below. Offline
checks succeeded against **6.0.274403**. The full hardware checklist, firmware
**4.x** regression checks, and **5.18.270971** runtime execution remain pending.
Successful startup is not evidence of complete GNSS or all-firmware support.

Development now continues on XCSoar's `kobo-nickel-compat` branch without
updating the pending upstream PR's source branch. The artifacts below were
built before the migration commits; their source manifests and patches
identify the uncommitted source snapshots. Rebuild after committing so new
release binaries embed the new revision.

## Artifact and source

Historical initial migration archive (superseded by the follow-ups below):
`dist-qt6/xcsoar-kobo-clara-colour-qt6-migration-20260930-final.zip`

SHA-256:
`33f2a21c820215816492c4bd9beceda0e43cd97d319888259d09a036907ad32e`

XCSoar executable SHA-256:
`2f7a96c9c5403417156755b74589781b962aa29050a6705aa70b60c4558baf4d`

Bundled FBInk SHA-256:
`22cfbc2ebdc71c78d067e0ea07426ec2e8c7ae8d003ed5f3fc94acabe473c250`

XCSoar branch: `kcc-gcc14-pr`, base commit
`5a4b31ce6d3e9e37985dd3f4be6cc62755cc12bd`, with the local migration changes.
The package contains a fingerprint of the built sources and patches including
new files, so the base commit alone is not the artifact's complete identity.

NickelTC base: `fcf553ad9f1c2b197dc05b82cccdc07c88107094`.
Packaging repository base: `6d8c005afb10527602fef6c1e29231b118f8d2bb`.
Compiler: GCC 14.3.0, crosstool-NG 1.28.0, ARM hard-float.
Image: `nickeltc-gcc14`, local image ID
`sha256:a9a4d072ca33d5917a8fd295ff85e4f7d5fc2972406b9a09459bde9356467c55`.
FBInk pin retained: `886f25f13368859ad8a899b88d04c26e19cda32e`.

## Passed checks

- `TARGET=KOBO_NICKEL DEBUG=n WERROR=y` build through `build-xcsoar.sh`.
- 33 ARM model cases under QEMU with the firmware 6 loader/libc: source
  priority and offsets, legacy fallback, missing/truncated/unknown data,
  interrupted and partial reads, B&W/Colour prefixes and display/Wi-Fi defaults.
- 25 ARM input cases: mocked evdev capability ioctls, rejection of stylus and
  accelerometer candidates, supported touch protocols, explicit override
  authority, alias ordering, numeric event ordering, absent candidates, and
  refusal to fall through after a candidate reports a grab/open failure.
- 11 launcher fixtures under both the system shell and BusyBox `sh`:
  concurrent/duplicate launch, normal stop, child failure, preservation of
  stopped processes and existing profiles, supervisor crash, stale relaunch,
  PID reuse rejection, missing UART, unknown UART owner preservation,
  termios restoration using the saved UART, and retained recovery state on
  UART restoration failure. Fixtures use disposable processes and PTYs.
- ELF validator passes for both XCSoar and FBInk. No Qt dependency, dynamic
  libstdc++/libgcc, or dynamic GLIBCXX/CXXABI imports. Maximum GLIBC requirement:
  XCSoar 2.17; FBInk 2.4. Interpreter `/lib/ld-linux-armhf.so.3`.
- `RUNPATH=$ORIGIN/lib`, with the obsolete Qt5 search path removed.
- Firmware loader resolves FBInk from `/package/lib/libfbink.so.1` and the
  remaining dependencies from firmware libraries.
- `LD_BIND_NOW=1` version-only execution succeeds, printing `7.45-Kobo`, using
  the firmware loader and an explicit package/firmware library path.
- Direct version-only execution also succeeds with `LD_LIBRARY_PATH` unset,
  exercising the final application's `$ORIGIN/lib` lookup.
- ZIP integrity and the packaged payload checksums pass; repository diffs
  have no whitespace errors.

The official firmware archive's SHA-256 matches the handoff:
`31d1462b3c7ae9f850c04b752b654404407cc4605c50885318a876ddb3b9ce47`.
Its `update.tar` matches the existing extracted update archive. The tested
rootfs's libc and loader bytes match those in the extracted raw rootfs image;
libc exports GLIBC_2.35. Firmware checks ran in disposable containers with
read-only package/rootfs mounts, networking disabled, and no real Kobo device
nodes. No launcher was run against firmware in the host environment.

Reproduce the final runtime check with:

```sh
./scripts/check-firmware-runtime.sh /tmp/nm6-rootfs-full \
  dist-qt6/xcsoar-kobo-clara-colour-qt6-migration-20260930-final
```

## Still required on hardware

Inspect the current firmware, active watchdog/services, touch aliases and
capabilities, UART owner/respawn source, and receiver configuration before
launching. Confirm N367 model selection without profile overrides, 300 DPI,
colour display defaults, `wlan0`, and model-specific battery/backlight paths.

Validate input ownership and actual EVIOCGRAB release, coordinates at every
corner, drags/releases, all intended rotations, and return to Nickel. The
input unit tests use mocked capabilities/candidate results; they do not test
kernel input grabs, physical event streams, screen alignment, or rendering.

Check display refresh/fences, normal exit, failure and emergency stop, real
GNSS NMEA reception, UART/console restoration, watchdog stability, Wi-Fi,
cold boot, repeated launches, and suspend/USB usability after exit. Repeat
offline and hardware checks for firmware 5.18.270971 before declaring support
for that exact firmware.

The agent did not deploy or launch on the physical device: the Kobo SSH
address was not supplied. Device launches and the success report came from
the owner.

## Device follow-up: start_getty owns ttyS0

The owner subsequently tried launching on the device. The log showed that
`getty` PID 4919 held `/dev/ttyS0`, supervised by `start_getty` PID 4915. Startup
stopped at the UART ownership check before launching XCSoar.

The extracted firmware's `/bin/start_getty` waits for a foreground
`/sbin/getty` child. `/etc/init.d/console-setup` generates a `respawn` entry
for that wrapper in `/etc/inittab` from the kernel console settings. The
launcher now recognizes that exact getty/wrapper pairing. It records and
suspends the wrapper, confirms the stopped state before terminating getty,
and restores termios before resuming the recorded wrapper. The wrapper can
then exit and init can respawn its console normally. Arbitrary UART owners
and interactive logins remain unsupported. Recovery also finishes getty
termination when setup was interrupted.

All 15 launcher fixtures pass under both the system shell and BusyBox `sh`.
New fixtures model init's respawn behavior with a real PTY and prove console
restoration after normal stop, XCSoar failure, or supervisor SIGKILL. They
also cover the legacy `kobo_getty.sh` pairing. The resumed console observes
the saved termios before acquiring the UART. Device UI/GNSS operation after
this change still needs an owner-run check.

Updated archive:
`dist-qt6/xcsoar-kobo-clara-colour-qt6-migration-20260930-getty-fix.zip`

SHA-256:
`d6ca42aee3e2a31accb1413b7d278bdbaca30c101c02e3ee05b944e13b6bdbee`

Only `xcsoar-common.sh` changes in the installed runtime payload; the XCSoar
binary and bundled FBInk retain the hashes and offline evidence above. ZIP
integrity and payload checksums pass. For a minimal update, replace the
installed helper with `scripts/xcsoar-common.sh` and retry the normal launch.

## Device follow-up: touch capability rejection

The next device log confirms that the launcher released `ttyS0` from getty
and resumed all recorded wrappers/services after XCSoar exited. XCSoar
rejected `/dev/input/tablet` and `event0` through `event2` as unsuitable for
touch. That log does not identify their actual capability bits; a device
`/proc/bus/input/devices` dump has been requested.

Inspection found a gap in the new filter: type-A multitouch devices with
MT position axes and `BTN_TOUCH`, but no slot axis, were rejected although
the existing event reader supports that protocol. The filter now accepts
these devices, with or without tracking IDs. Only slot-protocol devices
derive press/release from tracking IDs; type-A devices retain `BTN_TOUCH`
handling. Stylus rejection and exclusive input ownership remain unchanged.
Each queried candidate now logs its device name and relevant capability
bits, so any remaining rejection can be diagnosed from the launch log.

The GCC14 release build passes. All 29 ARM input regression cases pass
under the firmware 6 loader/libc, including the added type-A capability
cases. These are capability/discovery tests, not physical event-stream
tests. The updated package passes the firmware runtime check, eager-binding
version execution, direct version execution with `LD_LIBRARY_PATH` unset,
ZIP integrity, payload checksums, and whitespace checks. Physical touch
selection, coordinates, and press/release still require a device retry.

Updated archive (includes the getty fix and replaces the XCSoar binary):
`dist-qt6/xcsoar-kobo-clara-colour-qt6-migration-20260930-touch-fix.zip`

Archive SHA-256:
`447d9fe9efd3841a29c31fffc1618f8d5a40faca2e5be1257ed140332f8a1d95`

XCSoar binary SHA-256:
`9cd9fd518da9a0e6548c1b41b785b493942c437b3662f38146b220772f1059ff`

Updating only the launcher helper is insufficient for this follow-up.

## Device follow-up: cyttsp5_mt also advertises pen support

The owner's next launch log supplies the missing capability evidence:
`/dev/input/tablet` and `event1` are the same `cyttsp5_mt` controller, with
`xy=1 mt_xy=1 slots=0 tracking_id=1 BTN_TOUCH=1 direct=1 pen=1 KEY_POWER=1`.
The remaining rejection was caused by the blanket `!pen` condition, not
the coordinate or contact protocol. Advertising pen capability does not
make this combined direct multitouch controller a pen-only device.

The filter now permits pen capability when a device has both direct-input
and multitouch-position capabilities, provided it also meets the existing
supported contact-protocol checks. Pen-only nodes, accelerometers, and
unsupported contact protocols remain rejected. This is capability-based,
not a device-name whitelist. The event reader and coordinate transform are
unchanged by this follow-up; the reported legacy axes and `BTN_TOUCH` select
the existing legacy-coordinate path. Touch/power alias exclusion remains
in place, so the touch node cannot also be opened for the power role.

The GCC14 release build and all 34 ARM input cases pass. The regression
fixture mocks the exact reported capability combination through evdev
ioctls and checks that it is accepted, while direct pen-only devices remain
rejected. Combined slot-protocol finger/pen devices are also covered. The
firmware 6 runtime check passes: dependencies resolve, eager-binding version
execution succeeds, and direct version execution with `LD_LIBRARY_PATH`
unset succeeds. ZIP integrity and packaged payload checksums pass. Physical selection, touch
coordinates, and press/release still require a device retry.

Updated archive:
`dist-qt6/xcsoar-kobo-clara-colour-qt6-migration-20260930-cyttsp5-fix.zip`

Archive SHA-256:
`0e7371d018327252d779c391fd21306d8415b5d2e05b8724913ebec29ebc3f8c`

XCSoar binary SHA-256:
`a4727948fbba212188cacf35bdfa8ed6fd44b3515b7018371db0133ea01d070c`

The launcher/helper and bundled FBInk are unchanged from the touch-fix
package. Replacing the installed XCSoar executable is sufficient for this
follow-up; merely updating the helper is not.

## Pre-commit cleanup

Code cleanup preserves capability selection and coordinate handling, and
corrects comments/formatting and the power-device diagnostic. Packaging now
resolves relative `OUTPUT_DIR` paths before creating the ZIP. CI and the
README select `kobo-nickel-compat`; generated packages remain ignored.

The cleaned-up release build, 33 ARM model cases, 34 ARM input cases, and all
15 launcher fixtures under both system `sh` and BusyBox `sh` pass. Shell
syntax, whitespace, and ELF checks pass. Packaging with `OUTPUT_DIR=dist-qt6`
produces a valid ZIP whose payload hashes pass. The cleaned-up package also
passes the isolated firmware 6 runtime check, including eager binding and
direct execution with `LD_LIBRARY_PATH` unset. It has not been retried on
hardware; the owner's success report applies to the preceding cyttsp5
package.

Local cleanup archive:
`dist-qt6/xcsoar-kobo-clara-colour-qt6-migration-20260930-cleanup.zip`

SHA-256:
`b623d8c1828fe3155c477de6eada56a31126a561e73eea70ff5515e4dbc3ed6c`
