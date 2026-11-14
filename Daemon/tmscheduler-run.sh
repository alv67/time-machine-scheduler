#!/bin/bash
set -uo pipefail

CONF="/Library/Application Support/TMScheduler/config.json"
LOG="/Library/Application Support/TMScheduler/tmscheduler.log"
STATE="/Library/Application Support/TMScheduler/last-run.json"
TM_PLIST="/Library/Preferences/com.apple.TimeMachine.plist"
TEMP_EXCL="/Library/Application Support/TMScheduler/temporary-exclusions.txt"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

jget() { /usr/bin/plutil -extract "$1" raw -o - "$CONF" 2>/dev/null; }

write_state() { # <result> <durationSeconds> [limited] [excluded]
    local extra=""
    if [ "${3:-0}" = "1" ]; then
        extra=",\"limited\":true,\"excluded\":${4:-0}"
    fi
    printf '{"date":"%s","result":"%s","durationSeconds":%s%s}\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" "$2" "$extra" > "$STATE"
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

if [ "$SKIP_BATTERY" = "true" ] && /usr/bin/pmset -g batt | /usr/bin/grep -q 'Battery Power'; then
    rotate_log
    log "skip: Mac is on battery"
    exit 0
fi

DEST_PLIST="$(/usr/bin/tmutil destinationinfo -X 2>/dev/null || true)"

if [ "$REQUIRE_DEST" = "true" ]; then
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

# `tmutil startbackup --block` esce 0 anche quando il backup fallisce: l'esito vero è la
# comparsa di uno snapshot più recente. Il conteggio non serve: il thinning di Time Machine
# cancella i backup vecchi e il numero può calare mentre ne appare uno nuovo.
latest_snapshot() {
    local idx
    idx="$(destination_index)"
    /usr/bin/plutil -extract "Destinations.$idx.SnapshotDates" xml1 -o - "$TM_PLIST" 2>/dev/null \
        | /usr/bin/sed -n 's#.*<date>\(.*\)</date>.*#\1#p' \
        | /usr/bin/sort | /usr/bin/tail -1
}

backup_result() {
    local idx
    idx="$(destination_index)"
    /usr/bin/plutil -extract "Destinations.$idx.RESULT" raw -o - "$TM_PLIST" 2>/dev/null || true
}

result_reason() { # <RESULT>
    case "$1" in
        80) printf 'device locked (RESULT 80)' ;;
        "") printf 'unknown RESULT' ;;
        *) printf 'RESULT %s' "$1" ;;
    esac
}

# Con la sessione bloccata alcuni file di ~/Library non sono leggibili e Time Machine
# abbandona il run. Escluderli per questa sola esecuzione è meglio di nessun backup:
# si perdono preferenze e cache di quella notte, non i documenti.
limited_paths() {
    local home uid
    for home in /Users/*; do
        case "$home" in
            */Shared) continue ;;
        esac
        [ -d "$home/Library" ] || continue
        uid="$(/usr/bin/stat -f '%u' "$home" 2>/dev/null || echo 0)"
        [ "$uid" -ge 501 ] || continue
        printf '%s\n' "$home/Library"
    done
}

restore_exclusions() { # <file>
    local path
    [ -f "$1" ] || return 0
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        /usr/bin/tmutil removeexclusion -p "$path" >/dev/null 2>&1 || true
    done < "$1"
    /bin/rm -f "$1"
}

# Un run interrotto prima del ripristino lascerebbe esclusioni permanenti: si ripuliscono
# all'inizio di ogni esecuzione.
if [ -f "$TEMP_EXCL" ]; then
    restore_exclusions "$TEMP_EXCL"
    log "recovered: temporary exclusions removed"
fi

rotate_log
log "start"
write_state running 0
START=$(/bin/date +%s)
BEFORE="$(latest_snapshot)"

LIMITED=0
EXCLUDED=0
if [ "${TMS_LIMITED:-0}" = "1" ]; then
    : > "$TEMP_EXCL"
    while IFS= read -r path; do
        if /usr/bin/tmutil isexcluded "$path" 2>/dev/null | /usr/bin/grep -q "\[Excluded\]"; then
            continue
        fi
        if /usr/bin/tmutil addexclusion -p "$path" >/dev/null 2>&1; then
            printf '%s\n' "$path" >> "$TEMP_EXCL"
            EXCLUDED=$((EXCLUDED + 1))
        fi
    done < <(limited_paths)
    LIMITED=1
    log "limited: $EXCLUDED paths excluded for this run"
fi

if [ "$PREVENT_SLEEP" = "true" ]; then
    /usr/bin/caffeinate -i /usr/bin/tmutil startbackup --auto --block
else
    /usr/bin/tmutil startbackup --auto --block
fi
RC=$?

if [ "$LIMITED" = "1" ]; then
    restore_exclusions "$TEMP_EXCL"
    log "limited: exclusions restored"
fi

# Time Machine scrive lo snapshot (e RESULT) qualche secondo dopo la fine del run.
ATTEMPTS=0
AFTER="$(latest_snapshot)"
while [ "$ATTEMPTS" -lt 5 ]; do
    [[ "$AFTER" > "$BEFORE" ]] && break
    [ "$RC" -ne 0 ] && break
    /bin/sleep 3
    ATTEMPTS=$((ATTEMPTS + 1))
    AFTER="$(latest_snapshot)"
done

END=$(/bin/date +%s)
DURATION=$((END - START))

if [[ "$AFTER" > "$BEFORE" ]]; then
    write_state success "$DURATION" "$LIMITED" "$EXCLUDED"
    if [ "$LIMITED" = "1" ]; then
        log "end: success duration=${DURATION}s (limited: $EXCLUDED paths)"
        [ "$DO_NOTIFY" = "true" ] && notify "Limited backup completed: $EXCLUDED paths excluded"
    else
        log "end: success duration=${DURATION}s"
        [ "$DO_NOTIFY" = "true" ] && notify "Backup completed in ${DURATION}s"
    fi
else
    # Time Machine scrive RESULT qualche secondo dopo la fine del run, e la lettura
    # può fallire mentre la preferenza viene riscritta: un solo ritentativo.
    RESULT_CODE="$(backup_result)"
    if [ -z "$RESULT_CODE" ]; then
        /bin/sleep 5
        RESULT_CODE="$(backup_result)"
    fi
    REASON="$(result_reason "$RESULT_CODE")"
    [ "$RC" -ne 0 ] && REASON="tmutil rc=$RC / $REASON"
    write_state failed "$DURATION" "$LIMITED" "$EXCLUDED"
    log "end: failed $REASON duration=${DURATION}s"
    [ "$DO_NOTIFY" = "true" ] && notify "Backup failed: $REASON"
fi
