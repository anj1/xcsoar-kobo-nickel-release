#!/bin/sh
set -eu

APPDIR="/mnt/onboard/.adds/xcsoar"
LOGDIR="$APPDIR/logs"
PIDFILE="$APPDIR/xcsoar.pid"
CHILDPIDFILE="$APPDIR/xcsoar.child.pid"
DATADIR="/mnt/onboard/XCSoarData"
DEFAULT_PROFILE="$DATADIR/default.prf"
PACKAGED_PROFILE="$APPDIR/default-kobo-gnss.prf"
SERIAL_GETTY_PIDFILE="$APPDIR/serial-getty.pid"
GNSS_SERIAL_PORT="/dev/ttyS0"

pause_nickel() {
  for name in nickel sickel fontickel; do
    for pid in $(pidof "$name" 2>/dev/null || true); do
      kill -STOP "$pid" 2>/dev/null || true
    done
  done
}

resume_nickel() {
  for name in nickel sickel fontickel; do
    for pid in $(pidof "$name" 2>/dev/null || true); do
      kill -CONT "$pid" 2>/dev/null || true
    done
  done
}

pause_serial_getty() {
  : > "$SERIAL_GETTY_PIDFILE"

  for wrapper in $(pidof kobo_getty.sh 2>/dev/null || true); do
    if kill -STOP "$wrapper" 2>/dev/null; then
      echo "CONT $wrapper" >> "$SERIAL_GETTY_PIDFILE"
    fi
  done

  release_serial_tty
  sleep 1
  release_serial_tty -9
}

release_serial_tty() {
  signal="${1:-}"

  for fd in /proc/[0-9]*/fd/*; do
    target="$(readlink "$fd" 2>/dev/null || true)"
    [ "$target" = "$GNSS_SERIAL_PORT" ] || continue

    pid="${fd#/proc/}"
    pid="${pid%%/*}"
    [ "$pid" != "$$" ] || continue

    if [ -n "$signal" ]; then
      kill "$signal" "$pid" 2>/dev/null || true
    else
      kill "$pid" 2>/dev/null || true
    fi
  done
}

resume_serial_getty() {
  [ -f "$SERIAL_GETTY_PIDFILE" ] || return

  while read -r action pid; do
    case "$action" in
      CONT)
        [ -n "$pid" ] && kill -CONT "$pid" 2>/dev/null || true
        ;;
      *)
        [ -n "$action" ] && kill -CONT "$action" 2>/dev/null || true
        ;;
    esac
  done < "$SERIAL_GETTY_PIDFILE"

  rm -f "$SERIAL_GETTY_PIDFILE"
}

install_default_profile() {
  mkdir -p "$DATADIR"

  if [ ! -f "$DEFAULT_PROFILE" ] && [ -f "$PACKAGED_PROFILE" ]; then
    cp "$PACKAGED_PROFILE" "$DEFAULT_PROFILE"
    echo "Installed default GNSS profile: $DEFAULT_PROFILE"
  fi
}

mkdir -p "$LOGDIR"
ulimit -c unlimited || true

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "Already running: $(cat "$PIDFILE")" >> "$LOGDIR/xcsoar.log"
  exit 0
fi

export LD_LIBRARY_PATH="$APPDIR/lib:/usr/local/Kobo:/usr/local/Qt-5.2.1-arm/lib:${LD_LIBRARY_PATH:-}"
export KOBO_TOUCH_DEVICE="${KOBO_TOUCH_DEVICE:-}"
export HOME="$APPDIR"

cd "$APPDIR"

(
  cleanup() {
    status="${1:-0}"
    if [ -f "$CHILDPIDFILE" ]; then
      child_pid="$(cat "$CHILDPIDFILE")"
      kill "$child_pid" 2>/dev/null || true
      sleep 1
      kill -9 "$child_pid" 2>/dev/null || true
      rm -f "$CHILDPIDFILE"
    fi
    resume_serial_getty
    resume_nickel
    rm -f "$PIDFILE"
    exit "$status"
  }

  trap 'cleanup 143' INT TERM HUP

  echo "==== start $(date) ===="
  echo "cwd=$(pwd)"
  echo "args=${XCSOAR_ARGS:-}"
  echo "core_limit=$(ulimit -c)"
  cat /proc/sys/kernel/core_pattern 2>/dev/null || true
  install_default_profile
  pause_serial_getty
  pause_nickel
  ./xcsoar ${XCSOAR_ARGS:-} &
  echo "$!" > "$CHILDPIDFILE"
  set +e
  wait "$!"
  status="$?"
  set -e
  rm -f "$CHILDPIDFILE"
  resume_serial_getty
  resume_nickel
  rm -f "$PIDFILE"
  echo "==== exit $status $(date) ===="
  exit "$status"
) >> "$LOGDIR/xcsoar.log" 2>&1 &

echo "$!" > "$PIDFILE"
