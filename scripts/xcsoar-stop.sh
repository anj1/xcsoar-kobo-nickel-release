#!/bin/sh
set -eu
umask 077

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/xcsoar-common.sh"

exec >> "$LOGDIR/xcsoar.log" 2>&1

if record_alive "$SESSION/supervisor"; then
    read -r supervisor_pid supervisor_start < "$SESSION/supervisor"
    echo "stopping supervisor $supervisor_pid"
    signal_record "$SESSION/supervisor" TERM
    stop_attempt=0
    while record_alive "$SESSION/supervisor" && [ "$stop_attempt" -lt 10 ]; do
        sleep 1
        stop_attempt=$((stop_attempt + 1))
    done
    if record_alive "$SESSION/supervisor"; then
        signal_record "$SESSION/supervisor" KILL
        sleep 1
    fi
fi

# Shared recovery also handles SIGKILL and stop without an active session.
recover_session
