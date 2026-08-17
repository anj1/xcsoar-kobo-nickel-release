#!/bin/sh
set -eu

APPDIR="/mnt/onboard/.adds/xcsoar"
PIDFILE="$APPDIR/xcsoar.pid"
CHILDPIDFILE="$APPDIR/xcsoar.child.pid"
SERIAL_GETTY_PIDFILE="$APPDIR/serial-getty.pid"
GNSS_SERIAL_PORT="/dev/ttyS0"

resume_nickel() {
  for name in nickel sickel fontickel; do
    for pid in $(pidof "$name" 2>/dev/null || true); do
      kill -CONT "$pid" 2>/dev/null || true
    done
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

if [ -f "$PIDFILE" ]; then
  PID="$(cat "$PIDFILE")"
  kill "$PID" 2>/dev/null || true
  sleep 1
  kill -9 "$PID" 2>/dev/null || true
  rm -f "$PIDFILE"
fi

if [ -f "$CHILDPIDFILE" ]; then
  PID="$(cat "$CHILDPIDFILE")"
  kill "$PID" 2>/dev/null || true
  sleep 1
  kill -9 "$PID" 2>/dev/null || true
  rm -f "$CHILDPIDFILE"
fi

release_serial_tty
sleep 1
release_serial_tty -9
resume_serial_getty
resume_nickel
