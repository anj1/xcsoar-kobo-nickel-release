#!/bin/sh
set -eu
umask 077

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/xcsoar-common.sh"

supervisor_main()
{
    if [ "$HAVE_FLOCK" = 1 ]; then
        if ! lock_session -n; then
            echo "XCSoar is already starting or running"
            exit 0
        fi
    fi
    # mkdir is the atomic launch lock. No device state changes precede it.
    if ! mkdir "$SESSION" 2>/dev/null; then
        if record_alive "$SESSION/supervisor"; then
            echo "XCSoar is already running"
            exit 0
        fi
        sleep 1
        if record_alive "$SESSION/supervisor"; then
            exit 0
        fi
        recover_session || exit 1
        mkdir "$SESSION" 2>/dev/null || exit 0
    fi
    record_process "$$" > "$SESSION/supervisor"

    trap 'cleanup $?' EXIT
    trap 'cleanup 130' INT
    trap 'cleanup 143' TERM
    trap 'cleanup 129' HUP

    echo "start $(date): supervisor=$$ GNSS=$XCSOAR_GNSS port=$GNSS_SERIAL_PORT"
    install_default_profile

    if [ "$XCSOAR_GNSS" = on ]; then
        save_serial_state
        pause_serial_owner
    fi
    pause_nickel

    export LD_LIBRARY_PATH="$APPDIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    cd "$APPDIR"

    if [ "$XCSOAR_GNSS" = off ]; then
        set -- -simulator
    else
        set --
    fi
    # XCSOAR_ARGS is intentionally a whitespace-separated argument list.
    ./xcsoar ${XCSOAR_ARGS:-} "$@" 9>&- &
    child_pid=$!
    # A child can exit before /proc is inspected; wait still preserves status.
    record_process "$child_pid" > "$SESSION/child" || true

    set +e
    wait "$child_pid"
    status=$?
    set -e
    rm -f "$SESSION/child"
    exit "$status"
}

cleanup()
{
    cleanup_status=${1:-0}
    trap - EXIT INT TERM HUP
    recover_session || cleanup_status=1
    echo "exit $cleanup_status $(date)"
    exit "$cleanup_status"
}

if [ "${1:-}" = --supervisor ]; then
    supervisor_main
else
    /bin/sh "$0" --supervisor >> "$LOGDIR/xcsoar.log" 2>&1 &
fi
