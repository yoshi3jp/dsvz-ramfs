#!/bin/busybox sh
# shellcheck shell=dash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Minimal host-side Droidspaces supervisor.
#
# This file is sourced by /init.  /init remains host PID 1; Droidspaces is a
# child process and may independently create PID 1 inside a container PID
# namespace.  The functions deliberately avoid daemon restart policy while
# the guest command interface is still being established.

DS_SUPERVISOR_PID=

# Start Droidspaces as a supervised child.  Arguments are passed directly to
# the Droidspaces binary.  A second launch is rejected until the first child
# has been collected with droidspaces_wait.
droidspaces_start() {
    if [ ! -x /sbin/droidspaces ]; then
        log "Droidspaces binary is missing or not executable: /sbin/droidspaces"
        return 1
    fi

    if [ -n "${DS_SUPERVISOR_PID:-}" ]; then
        log "Droidspaces is already supervised as pid=$DS_SUPERVISOR_PID"
        return 1
    fi

    /sbin/droidspaces "$@" &
    DS_SUPERVISOR_PID=$!
    log "started Droidspaces pid=$DS_SUPERVISOR_PID"
}

# Forward an external lifecycle signal to the immediate Droidspaces child.
# Container-specific shutdown remains Droidspaces' responsibility.
droidspaces_forward_signal() {
    DS_SUPERVISOR_SIGNAL=${1:-}

    case "$DS_SUPERVISOR_SIGNAL" in
        TERM|INT|HUP|QUIT) ;;
        *)
            log "refusing unsupported Droidspaces signal: $DS_SUPERVISOR_SIGNAL"
            return 2
            ;;
    esac

    [ -n "${DS_SUPERVISOR_PID:-}" ] || return 0

    if kill -0 "$DS_SUPERVISOR_PID" 2>/dev/null; then
        log "forwarding SIG$DS_SUPERVISOR_SIGNAL to Droidspaces pid=$DS_SUPERVISOR_PID"
        kill "-$DS_SUPERVISOR_SIGNAL" "$DS_SUPERVISOR_PID" 2>/dev/null || true
    fi
}

# Wait for the immediate child.  Signal traps can interrupt wait(), so retain
# PID 1 and keep waiting while the child is still alive.  The child exit
# status is returned to /init after its PID has been cleared.
droidspaces_wait() {
    DS_SUPERVISOR_STATUS=0

    [ -n "${DS_SUPERVISOR_PID:-}" ] || return 0

    while :; do
        wait "$DS_SUPERVISOR_PID"
        DS_SUPERVISOR_STATUS=$?

        if kill -0 "$DS_SUPERVISOR_PID" 2>/dev/null; then
            log "Droidspaces wait interrupted; child is still running"
            continue
        fi

        DS_SUPERVISOR_PID=
        return "$DS_SUPERVISOR_STATUS"
    done
}
