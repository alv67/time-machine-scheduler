#!/bin/bash
set -uo pipefail

CONF="/Library/Application Support/TMScheduler/config.json"
LOG="/Library/Application Support/TMScheduler/tmscheduler.log"
STATE="/Library/Application Support/TMScheduler/last-run.json"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

jget() { /usr/bin/plutil -extract "$1" raw -o - "$CONF" 2>/dev/null; }

write_state() { # <result> <durationSeconds>
    printf '{"date":"%s","result":"%s","durationSeconds":%s}\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" "$2" > "$STATE"
}

rotate_log() {
    [ -f "$LOG" ] || return 0
    [ "$(/usr/bin/stat -f%z "$LOG")" -gt 1048576 ] || return 0
    /bin/mv -f "$LOG.2" "$LOG.3" 2>/dev/null || true
    /bin/mv -f "$LOG.1" "$LOG.2" 2>/dev/null || true
    /bin/mv -f "$LOG" "$LOG.1"
}

host_reachable() {
    /sbin/ping -c1 -t2 "$1" >/dev/null 2>&1 && return 0
    /usr/bin/nc -z -G2 -w2 "$1" 445 >/dev/null 2>&1 && return 0
    return 1
}

# La destinazione viene letta da Time Machine: nessun host hardcoded.
DEST_PLIST=""

dest_field() {
    printf '%s' "$DEST_PLIST" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null || true
}

destination_index() {
    local i
    for i in 0 1 2 3 4 5 6 7 8 9; do
        if [ "$(dest_field "Destinations.$i.LastDestination")" = "1" ]; then
            printf '%s' "$i"
            return
        fi
    done
    printf '0'
}

destination_host() {
    local url
    url="$(dest_field "Destinations.$(destination_index).URL")"
    printf '%s' "$url" | /usr/bin/sed -E \
        's#^[A-Za-z][A-Za-z0-9+.-]*://##; s#^[^@/]*@##; s#/.*$##; s#:[0-9]+$##'
}

# I nomi Bonjour (es. nas._smb._tcp.local.) non si risolvono con ping: dns-sd li traduce.
service_host() {
    local host="$1" instance service out pid
    case "$host" in
        *._smb._tcp.local.) instance="${host%._smb._tcp.local.}"; service="_smb._tcp" ;;
        *._afp._tcp.local.) instance="${host%._afp._tcp.local.}"; service="_afp._tcp" ;;
        *) return 1 ;;
    esac
    out="$(/usr/bin/mktemp "${STATE%/*}/dns.XXXXXX" 2>/dev/null)" || return 1
    /usr/bin/dns-sd -L "$instance" "$service" local. >"$out" 2>/dev/null &
    pid=$!
    /bin/sleep 2
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    /usr/bin/sed -n 's/.*can be reached at \([^:]*\):.*/\1/p' "$out" | /usr/bin/head -1
    /bin/rm -f "$out"
}

destination_reachable() {
    local host="$1" resolved
    [ -z "$host" ] && return 0
    case "$host" in
        *._smb._tcp.local.|*._afp._tcp.local.)
            resolved="$(service_host "$host")"
            [ -n "$resolved" ] && host_reachable "$resolved"
            return
            ;;
    esac
    host_reachable "$host" && return 0
    resolved="$(service_host "$host")"
    [ -n "$resolved" ] && host_reachable "$resolved"
}

notify() {
    local uid
    uid="$(/usr/bin/stat -f '%u' /dev/console)"
    [ "$uid" = "0" ] && return 0
    /bin/launchctl asuser "$uid" /usr/bin/osascript \
        -e "display notification \"$1\" with title \"Time Machine Scheduler\"" >/dev/null 2>&1 || true
}

[ -f "$CONF" ] || exit 0

[ "$(jget enabled)" = "true" ] || exit 0

REQUIRE_DEST="$(jget requireDestination)"
PREVENT_SLEEP="$(jget preventSleep)"
SKIP_BATTERY="$(jget skipOnBattery)"
DO_NOTIFY="$(jget notify)"

LAST_DATE="$(/usr/bin/plutil -extract date raw -o - "$STATE" 2>/dev/null || true)"
case "$LAST_DATE" in
    "$(date -u '+%Y-%m-%d')"*) exit 0 ;;
esac

if [ "$SKIP_BATTERY" = "true" ] && /usr/bin/pmset -g batt | /usr/bin/grep -q 'Battery Power'; then
    rotate_log
    log "skip: Mac is on battery"
    exit 0
fi

if [ "$REQUIRE_DEST" = "true" ]; then
    DEST_PLIST="$(/usr/bin/tmutil destinationinfo -X 2>/dev/null || true)"
    DEST_INDEX="$(destination_index)"
    DEST_KIND="$(dest_field "Destinations.$DEST_INDEX.Kind")"
    DEST_HOST="$(destination_host)"
    if [ -z "$DEST_KIND" ]; then
        rotate_log
        log "skip: no Time Machine destination configured"
        exit 0
    fi
    if [ "$DEST_KIND" = "Network" ] && ! destination_reachable "$DEST_HOST"; then
        rotate_log
        log "skip: destination $DEST_HOST unreachable"
        exit 0
    fi
fi

if /usr/bin/tmutil status -X 2>/dev/null | /usr/bin/plutil -extract Running raw -o - - 2>/dev/null | /usr/bin/grep -q true; then
    rotate_log
    log "skip: backup already running"
    exit 0
fi

rotate_log
log "start"
write_state running 0
START=$(/bin/date +%s)

if [ "$PREVENT_SLEEP" = "true" ]; then
    /usr/bin/caffeinate -i /usr/bin/tmutil startbackup --auto --block
else
    /usr/bin/tmutil startbackup --auto --block
fi
RC=$?

END=$(/bin/date +%s)
DURATION=$((END - START))

if [ "$RC" -eq 0 ]; then
    write_state success "$DURATION"
    log "end: success duration=${DURATION}s"
    [ "$DO_NOTIFY" = "true" ] && notify "Backup completed in ${DURATION}s"
else
    write_state failed "$DURATION"
    log "end: failed rc=$RC duration=${DURATION}s"
    [ "$DO_NOTIFY" = "true" ] && notify "Backup failed (rc=$RC)"
fi
