#!/bin/sh
# Shared POSIX/BusyBox-compatible supervisor state and recovery.

APPDIR=${XCSOAR_APPDIR:-/mnt/onboard/.adds/xcsoar}
LOGDIR="$APPDIR/logs"
DATADIR=${XCSOAR_DATADIR:-/mnt/onboard/XCSoarData}
SESSION=${XCSOAR_SESSION_DIR:-/tmp/xcsoar.session}
GNSS_SERIAL_PORT=${GNSS_SERIAL_PORT:-/dev/ttyS0}
XCSOAR_GNSS=${XCSOAR_GNSS:-on}
case "$XCSOAR_GNSS" in
    on|off) ;;
    *) echo "XCSOAR_GNSS must be on or off" >&2; exit 1 ;;
esac
mkdir -p "$LOGDIR"

# Qt6 firmware supplies util-linux flock. Retain the directory-lock fallback
# for older firmware; never unlink a flock file while another process uses it.
HAVE_FLOCK=0
command -v flock >/dev/null 2>&1 && HAVE_FLOCK=1
SESSION_LOCK_HELD=0

lock_session()
{
    [ "$SESSION_LOCK_HELD" = 0 ] || return 0
    exec 9> "$SESSION.lock"
    flock "$@" 9 || return 1
    SESSION_LOCK_HELD=1
}

process_fields()
{
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ -r "/proc/$1/stat" ] || return 1
    # comm can contain spaces and ')'; fields after its final ')' are numeric.
    pf_stat=$(cat "/proc/$1/stat") || return 1
    pf_stat=${pf_stat##*) }
    set -- $pf_stat
    pf_state=$1
    pf_parent=$2
    shift 19
    pf_start=$1
}

record_process()
{
    rp_pid=$1
    process_fields "$rp_pid" || return 1
    printf '%s %s\n' "$rp_pid" "$pf_start"
}

identity_alive()
{
    ia_pid=$1 ia_start=$2
    process_fields "$ia_pid" && [ "$pf_start" = "$ia_start" ] &&
        [ "$pf_state" != Z ] && [ "$pf_state" != X ]
}

record_alive()
{
    [ -s "$1" ] || return 1
    read -r ra_pid ra_start < "$1" || return 1
    identity_alive "$ra_pid" "$ra_start"
}

signal_record()
{
    sr_file=$1 sr_signal=$2
    if record_alive "$sr_file"; then
        read -r sr_pid sr_start < "$sr_file"
        kill "-$sr_signal" "$sr_pid" 2>/dev/null || true
    fi
}

pause_process()
{
    pp_pid=$1 pp_file=$2
    process_fields "$pp_pid" || return 0
    # Preserve processes already stopped before this launch.
    case "$pf_state" in T|t|Z|X) return 0 ;; esac
    pp_start=$pf_start
    printf '%s %s\n' "$pp_pid" "$pp_start" >> "$pp_file"
    if identity_alive "$pp_pid" "$pp_start"; then
        kill -STOP "$pp_pid" || return 1
        # Confirm STOP before terminating a wrapper's child; otherwise the
        # wrapper could exit and init could respawn it during UART takeover.
        pp_attempt=0
        while identity_alive "$pp_pid" "$pp_start"; do
            case "$pf_state" in T|t)
                echo "suspended pid=$pp_pid start=$pp_start"
                return 0 ;;
            esac
            [ "$pp_attempt" -lt 50 ] || {
                echo "ERROR: process $pp_pid did not stop"
                return 1
            }
            sleep 0.02
            pp_attempt=$((pp_attempt + 1))
        done
    fi
}

resume_processes()
{
    [ -f "$1" ] || return 0
    while read -r rr_pid rr_start; do
        if identity_alive "$rr_pid" "$rr_start"; then
            kill -CONT "$rr_pid" 2>/dev/null || true
            echo "resumed pid=$rr_pid start=$rr_start"
        fi
    done < "$1"
    rm -f "$1"
}

pause_nickel()
{
    # Suspend the known watchdog before the UI it watches.
    for pn_name in sickel fontickel nickel; do
        for pn_pid in $(pidof "$pn_name" 2>/dev/null || true); do
            pause_process "$pn_pid" "$SESSION/nickel"
        done
    done
}

pause_serial_owner()
{
    so_port=$(readlink -f "$GNSS_SERIAL_PORT") || return 1
    [ -c "$so_port" ] || {
        echo "ERROR: GNSS UART unavailable: $GNSS_SERIAL_PORT (use XCSOAR_GNSS=off for simulation)"
        return 1
    }
    for so_proc in /proc/[0-9]*; do
        so_pid=${so_proc##*/}
        [ "$so_pid" != "$$" ] || continue
        so_owns=0
        for so_fd in "$so_proc"/fd/*; do
            if [ "$(readlink -f "$so_fd" 2>/dev/null || true)" = "$so_port" ]; then
                so_owns=1
                break
            fi
        done
        [ "$so_owns" = 1 ] || continue
        so_name=$(cat "$so_proc/comm" 2>/dev/null || true)
        process_fields "$so_pid" || continue
        so_parent=$pf_parent
        so_parent_name=$(cat "/proc/$so_parent/comm" 2>/dev/null || true)
        # Both wrappers wait for getty as a foreground child. Holding the
        # wrapper stopped prevents it exiting and triggering init's respawn.
        # start_getty's actual ownership was confirmed by the device log;
        # its implementation is /bin/start_getty in the firmware rootfs.
        case "$so_name:$so_parent_name" in
            getty:kobo_getty.sh|agetty:kobo_getty.sh|\
            getty:start_getty|agetty:start_getty)
                process_fields "$so_parent" || return 1
                case "$pf_state" in T|t)
                    echo "ERROR: serial wrapper was already stopped; refusing to disturb it"
                    return 1 ;;
                esac
                pause_process "$so_parent" "$SESSION/serial-owner"
                echo "releasing $so_port from $so_name pid=$so_pid under $so_parent_name pid=$so_parent"
                record_process "$so_pid" > "$SESSION/getty"
                terminate_record "$SESSION/getty" || return 1
                ;;
            *)
                echo "ERROR: UART $so_port owned by pid=$so_pid ($so_name), parent=$so_parent ($so_parent_name). Stop its console/respawn service explicitly, or use XCSOAR_GNSS=off."
                return 1 ;;
        esac
    done
}

save_serial_state()
{
    ss_port=$(readlink -f "$GNSS_SERIAL_PORT") || return 1
    ss_identity=$(stat -Lc '%t:%T' "$ss_port") || return 1
    ss_state=$(stty -F "$ss_port" -g) || {
        echo "ERROR: unable to save UART termios: $ss_port"
        return 1
    }
    printf '%s\n%s\n%s\n' "$ss_port" "$ss_identity" "$ss_state" > "$SESSION/tty"
}

restore_serial_state()
{
    [ -s "$SESSION/tty" ] || return 0
    {
        read -r rs_port
        read -r rs_identity
        read -r rs_state
    } < "$SESSION/tty" || return 1
    if [ ! -c "$rs_port" ] ||
       [ "$(stat -Lc '%t:%T' "$rs_port")" != "$rs_identity" ]; then
        echo "ERROR: saved UART identity has changed: $rs_port"
        return 1
    fi
    for rs_attempt in 1 2 3; do
        if stty -F "$rs_port" "$rs_state"; then
            rm -f "$SESSION/tty"
            return 0
        fi
        sleep 1
    done
    echo "ERROR: cannot restore $rs_port; saved state retained"
    return 1
}

install_default_profile()
{
    mkdir -p "$DATADIR"
    ip_default="$DATADIR/default.prf"
    if [ ! -f "$ip_default" ]; then
        case "$GNSS_SERIAL_PORT" in *[!a-zA-Z0-9_./-]*|'')
            echo "ERROR: invalid GNSS_SERIAL_PORT"; return 1 ;;
        esac
        sed "s|^PortPath=.*|PortPath=\"$GNSS_SERIAL_PORT\"|" \
            "$APPDIR/default-kobo-gnss.prf" > "$ip_default"
    fi
    if [ "$XCSOAR_GNSS" = on ]; then
        ip_path=$(sed -n 's/^PortPath="\(.*\)"$/\1/p' "$ip_default")
        if [ "$ip_path" != "$GNSS_SERIAL_PORT" ]; then
            echo "ERROR: profile UART ($ip_path) differs from launcher ($GNSS_SERIAL_PORT). Set GNSS_SERIAL_PORT to match the profile."
            return 1
        fi
    fi
}

terminate_record()
{
    tr_file=$1
    if record_alive "$tr_file"; then
        read -r tr_pid tr_start < "$tr_file"
        signal_record "$tr_file" TERM
        signal_record "$tr_file" CONT
        tr_attempt=0
        while record_alive "$tr_file" && [ "$tr_attempt" -lt 3 ]; do
            sleep 1
            tr_attempt=$((tr_attempt + 1))
        done
        signal_record "$tr_file" KILL
        tr_attempt=0
        while record_alive "$tr_file" && [ "$tr_attempt" -lt 3 ]; do
            sleep 1
            tr_attempt=$((tr_attempt + 1))
        done
        if record_alive "$tr_file"; then
            echo "ERROR: process $tr_pid did not release its resources"
            return 1
        fi
        wait "$tr_pid" 2>/dev/null || true
    fi
    rm -f "$tr_file"
}

recover_session()
{
    if [ "$HAVE_FLOCK" = 1 ]; then
        lock_session -w 10 || {
            echo "Unable to acquire session cleanup lock"
            return 1
        }
    fi
    [ -d "$SESSION" ] || return 0
    if ! mkdir "$SESSION/cleanup-lock" 2>/dev/null; then
        if record_alive "$SESSION/cleanup-owner"; then
            echo "Session cleanup already in progress"
            return 1
        fi
        rmdir "$SESSION/cleanup-lock" 2>/dev/null || return 1
        mkdir "$SESSION/cleanup-lock" 2>/dev/null || return 1
    fi
    record_process "$$" > "$SESSION/cleanup-owner"

    recovery_status=0
    terminate_record "$SESSION/child" || recovery_status=1
    if [ "$recovery_status" = 0 ]; then
        # Also finish a UART takeover interrupted during getty termination.
        terminate_record "$SESSION/getty" || recovery_status=1
    fi
    if [ "$recovery_status" = 0 ]; then
        restore_serial_state || recovery_status=1
        if [ "$recovery_status" = 0 ]; then
            resume_processes "$SESSION/serial-owner"
        fi
    fi
    resume_processes "$SESSION/nickel"
    rm -f "$SESSION/cleanup-owner"
    rmdir "$SESSION/cleanup-lock"
    if [ "$recovery_status" = 0 ]; then
        rm -f "$SESSION/supervisor" "$SESSION/getty"
        rmdir "$SESSION"
    fi
    return "$recovery_status"
}
