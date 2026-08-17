# XCSoar for Kobo Clara Colour

This repository builds and packages the `KOBO_NICKEL` target of XCSoar for the Kobo Clara Colour. The resulting archive is installed under `.adds/xcsoar` and launched from NickelMenu.

The build uses the GCC 14 NickelTC image produced from [anj1/NickelTC](https://github.com/anj1/NickelTC). The XCSoar source is fetched from [anj1/XCSoar](https://github.com/anj1/XCSoar), branch `kobo-clara-colour-gcc14`, until the changes are available upstream.

## Simple Install

The simplest install is to just use the binary release directly. You need to install NickelMenu on your Kobo (if it's not already installed), then add the XCSoar menu entries, and finally copy over the binaries.

### Installing NickelMenu

Download KoboRoot.tgz from the following like and place it in the .kobo folder on your kobo.

https://github.com/jadehawk/Kobo-Essentials/tree/main/02%20-%20NickelMenu/Build%20%23775%20-%20GDrive%20Enabled/NickelMenu

A firmware update will commence, after which you'll have NickelMenu.

Then, modify the nickel menu config. Open up .adds/nm/config and add the following entries:

```
menu_item :main :XCSoar :cmd_spawn :quiet:/mnt/onboard/.adds/xcsoar/run.sh
menu_item :main :Stop XCSoar :cmd_spawn :quiet:/mnt/onboard/.adds/xcsoar/stop.sh
```

Finally, download the xcsoar build artifact from this repo, and unzip it into .adds/xcsoar. You should have the binary at .adds/xcsoar/xcsoar, the lib folder at .adds/xcsoar/lib, etc.

Then XCSoar should pop up in the nickel menu and it will run. Enjoy!

## Building XCSoar locally

If you want to build XCSoar for the Kobo Clara Colour locally, the instructions are as follows.

Requirements: Docker, Git, `zip`, `unzip`, `strings`, and DejaVu Sans fonts.

Place this repository and the XCSoar checkout beside one another, or set `XCSOAR_DIR` explicitly:

```sh
XCSOAR_DIR=/path/to/XCSoar \
  ./scripts/build-xcsoar.sh

XCSOAR_DIR=/path/to/XCSoar \
  ./scripts/package-xcsoar.sh
```

By default the scripts use the local image `nickeltc-gcc14`. Select another image with `IMAGE`, preferably a versioned image published by the NickelTC release workflow:

```sh
IMAGE=ghcr.io/anj1/nickeltc-gcc14:2026-08-13 ./scripts/build-xcsoar.sh
```

The package script writes a versioned ZIP to `dist/` and a matching unpacked directory. Override `RELEASE_VERSION` for local builds; CI derives it from the Git tag.

The image must contain the Nickel sysroot and FBInk. Build it from `NickelTC/Dockerfile.gcc14` in the NickelTC repository, then use the resulting image with `IMAGE`.

## Install on a Kobo

Install [NickelMenu](https://pgaskin.net/NickelMenu/), unzip the release, and copy the contents of the unpacked directory to:

```text
/mnt/onboard/.adds/xcsoar/
```

Add these entries to `.adds/nm/config`:

```ini
menu_item :main :XCSoar :cmd_spawn :quiet:/mnt/onboard/.adds/xcsoar/run.sh
menu_item :main :Stop XCSoar :cmd_spawn :quiet:/mnt/onboard/.adds/xcsoar/stop.sh
```

Eject the Kobo, restart NickelMenu, and launch XCSoar from the main menu. The first launch creates `/mnt/onboard/XCSoarData` and installs the packaged GNSS profile if no default profile exists.

## Release process

Pushing a tag matching `vX.Y.Z` runs the GitHub Actions release workflow. It checks out the configured XCSoar branch, builds with the configured NickelTC image, packages the binary, and attaches the ZIP and checksum to the GitHub release.

The release archive contains the XCSoar executable, launch/stop scripts, FBInk's shared library, DejaVu fonts, and the default GNSS profile. It does not contain the toolchain, source checkout, or development/test applications.

For optional SSH deployment, set the target explicitly before running the helper:

```sh
KOBO_HOST=root@kobo.local ./scripts/deploy-run-xcsoar-ssh.sh
```

## License

XCSoar is distributed under the GNU General Public License. See [LICENSE](LICENSE) and the upstream XCSoar repository for the complete licensing and third-party notices.
