#!/bin/bash
set -uo pipefail

CONF="/Library/Application Support/TMScheduler/config.json"
LOG="/Library/Application Support/TMScheduler/tmscheduler.log"
STATE="/Library/Application Support/TMScheduler/last-run.json"
TM_PLIST="/Library/Preferences/com.apple.TimeMachine.plist"
TEMP_EXCL="/Library/Application Support/TMScheduler/temporary-exclusions.txt"
LEARNED_EXCL="/Library/Application Support/TMScheduler/exclusions-learned.txt"
TM_DOMAIN="/Library/Preferences/com.apple.TimeMachine"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

jget() { /usr/bin/plutil -extract "$1" raw -o - "$CONF" 2>/dev/null; }

write_state() { # <result> <durationSeconds> [excluded]
    local result="$1" duration="$2" excluded="${3:-0}" extra=""
    case "$excluded" in
        ''|*[!0-9]*) excluded=0 ;;
    esac
    if [ "$excluded" -gt 0 ]; then
        extra=",\"limited\":true,\"excluded\":$excluded"
    fi
    printf '{"date":"%s","result":"%s","durationSeconds":%s%s}\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$result" "$duration" "$extra" > "$STATE"
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
LEARNED_ENABLED="$(jget limitedBackup)"
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

# Un run interrotto prima del ripristino lascerebbe esclusioni permanenti.
if [ -f "$TEMP_EXCL" ]; then
    restore_exclusions "$TEMP_EXCL"
    log "exclusions: restored after an interrupted run"
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
        48) printf 'destination mount dropped (RESULT 48)' ;;
        "") printf 'unknown RESULT' ;;
        *) printf 'RESULT %s' "$1" ;;
    esac
}

# Le esclusioni si scrivono direttamente in SkipPaths: `tmutil addexclusion` richiede
# Full Disk Access, che un demone di sistema non ha.
skip_paths() { # una riga per percorso escluso
    /usr/bin/defaults read "$TM_DOMAIN" SkipPaths 2>/dev/null \
        | /usr/bin/sed -n 's/^[[:space:]]*"\(.*\)",\{0,1\}$/\1/p'
}

write_skip_paths() { # stdin: una riga per percorso; nessuna riga = chiave rimossa
    local -a list=()
    local line
    while IFS= read -r line; do
        [ -n "$line" ] && list+=("$line")
    done
    if [ "${#list[@]}" -eq 0 ]; then
        /usr/bin/defaults delete "$TM_DOMAIN" SkipPaths >/dev/null 2>&1 || true
    else
        /usr/bin/defaults write "$TM_DOMAIN" SkipPaths -array "${list[@]}"
    fi
}

restore_exclusions() { # <file con i percorsi aggiunti da noi>
    local line
    local -a keep=()
    [ -f "$1" ] || return 0
    while IFS= read -r line; do
        /usr/bin/grep -qxF -- "$line" "$1" || keep+=("$line")
    done < <(skip_paths)
    if [ "${#keep[@]}" -gt 0 ]; then
        printf '%s\n' "${keep[@]}" | write_skip_paths
    else
        write_skip_paths < /dev/null
    fi
    /bin/rm -f "$1"
}

apply_learned_exclusions() {
    [ -s "$LEARNED_EXCL" ] || return 0
    local path
    : > "$TEMP_EXCL"
    while IFS= read -r path; do
        skip_paths | /usr/bin/grep -qxF -- "$path" && continue
        printf '%s\n' "$path" >> "$TEMP_EXCL"
    done < "$LEARNED_EXCL"
    [ -s "$TEMP_EXCL" ] || return 0
    { skip_paths; /bin/cat "$TEMP_EXCL"; } | write_skip_paths
    EXCLUDED=$(/usr/bin/wc -l < "$TEMP_EXCL" | /usr/bin/tr -d ' ')
    log "exclusions: $EXCLUDED learned paths excluded for this run"
}

# Dal run fallito si impara la lista dei percorsi protetti, accorpata alla profondità
# più profonda che resta sotto 10 voci per utente.
learn_from_failure() { # <data di inizio del run, formato di log show>
    local paths="$TEMP_EXCL.paths" grouped depth max
    /usr/bin/log show --info --start "$1" --predicate 'process == "backupd"' 2>/dev/null \
        | /usr/bin/grep -o 'Failed to backup [0-9]* paths[^]]*]' \
        | /usr/bin/sed 's/.*locked:\[//; s/"\]$//' \
        | /usr/bin/sed 's/", "/\n/g' \
        | /usr/bin/sed 's/^"//; s/^\\n//' \
        | /usr/bin/grep -E '^(Users|private)/' \
        | /usr/bin/sed 's#^#/#' \
        | /usr/bin/sort -u > "$paths"
    if [ ! -s "$paths" ]; then
        /bin/rm -f "$paths"
        return 1
    fi
    for depth in 7 6 5 4 3 2; do
        grouped="$(/usr/bin/cut -d/ -f1-$((depth + 1)) "$paths" | /usr/bin/sort -u)"
        max="$(printf '%s\n' "$grouped" | /usr/bin/awk -F/ '{print $3}' \
            | /usr/bin/sort | /usr/bin/uniq -c | /usr/bin/sort -rn | /usr/bin/head -1 \
            | /usr/bin/awk '{print $1}')"
        if [ "${max:-0}" -le 10 ]; then
            printf '%s\n' "$grouped" > "$LEARNED_EXCL"
            log "learned: $(printf '%s\n' "$grouped" | /usr/bin/wc -l | /usr/bin/tr -d ' ') exclusions, depth $depth, max $max per user"
            /bin/rm -f "$paths"
            return 0
        fi
    done
    /bin/rm -f "$paths"
    return 1
}

rotate_log
log "start"
write_state running 0
# L'esito si legge dalla destinazione, come fa backupd: il nome dell'ultimo backup
# contiene data e ora locali (YYYY-MM-DD-HHMMSS) e non dipende dalle preferenze di
# Time Machine, che durante il run vengono riscritte e risultano illeggibili.
latest_backup_epoch() {
    local name
    name="$(/usr/bin/tmutil latestbackup 2>/dev/null \
        | /usr/bin/sed -n 's#.*/\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-[0-9]\{6\}\)\.backup.*#\1#p' \
        | /usr/bin/tail -1)"
    [ -n "$name" ] || return 1
    /bin/date -j -f "%Y-%m-%d-%H%M%S" "$name" +%s 2>/dev/null
}

# Ripiego: la data più recente dalle preferenze, letta come UTC.
snapshot_epoch() {
    local date_str
    date_str="$(latest_snapshot)"
    [ -n "$date_str" ] || return 1
    TZ=UTC /bin/date -j -f "%Y-%m-%dT%H:%M:%SZ" "$date_str" +%s 2>/dev/null
}

outcome_epoch() {
    latest_backup_epoch || snapshot_epoch
}

# Stato della sessione: sbloccata non esclude niente; bloccata applica le esclusioni
# imparate; nessuna sessione (pagina di login) non arriva nemmeno qui, il daemon salta.
session_state() {
    local uid state
    uid="$(/usr/bin/stat -f %u /dev/console 2>/dev/null || echo 0)"
    [ "$uid" = "0" ] && { echo "none"; return; }
    state="$(/bin/launchctl asuser "$uid" /usr/local/bin/tmscheduler-daemon --session-state 2>/dev/null)"
    case "$state" in
        *locked=1*) echo "locked" ;;
        *onconsole=1*) echo "unlocked" ;;
        *) echo "none" ;;
    esac
}

# Un tentativo di backup. Aggiorna ATTEMPT_OK, RC, DURATION, AFTER, AFTER_EPOCH e
# gli estremi della finestra usata per riconoscere il successo.
attempt_backup() {
    local start before success_from found pid tries
    start=$(/bin/date +%s)
    ATTEMPT_START="$(/bin/date -r "$start" '+%Y-%m-%d %H:%M:%S')"
    before="$(latest_snapshot)"
    success_from=$((start - 120))
    # Il successo si riconosce mentre il run è in corso, appena il backup compare: alla
    # fine la destinazione viene smontata e le letture non sono più affidabili.
    if [ "$PREVENT_SLEEP" = "true" ]; then
        /usr/bin/caffeinate -i /usr/bin/tmutil startbackup --auto --block &
    else
        /usr/bin/tmutil startbackup --auto --block &
    fi
    pid=$!
    ATTEMPT_OK=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$ATTEMPT_OK" = "0" ]; then
            found="$(outcome_epoch || true)"
            if [ -n "$found" ] && [ "$found" -ge "$success_from" ]; then
                ATTEMPT_OK=1
            fi
        fi
        /bin/sleep 10
    done
    wait "$pid"
    RC=$?
    AFTER=""
    AFTER_EPOCH=0
    tries=0
    while [ "$tries" -lt 18 ] && [ "$ATTEMPT_OK" = "0" ]; do
        AFTER="$(latest_snapshot)"
        AFTER_EPOCH="$(outcome_epoch || echo 0)"
        [ "${AFTER_EPOCH:-0}" -ge "$success_from" ] && break
        /bin/sleep 10
        tries=$((tries + 1))
    done
    if [ "${AFTER_EPOCH:-0}" -ge "$success_from" ]; then
        ATTEMPT_OK=1
    fi
    BEFORE="$before"
    SUCCESS_FROM="$success_from"
    DURATION=$(( $(/bin/date +%s) - start ))
}

SESSION="$(session_state)"
log "session: $SESSION"

ATTEMPT=1
while :; do
    EXCLUDED=0
    if [ "$LEARNED_ENABLED" = "true" ] && [ "$SESSION" = "locked" ] && [ -s "$LEARNED_EXCL" ]; then
        apply_learned_exclusions
    fi

    attempt_backup

    if [ -f "$TEMP_EXCL" ]; then
        restore_exclusions "$TEMP_EXCL"
        log "exclusions: restored"
    fi

    if [ "$ATTEMPT_OK" = "1" ]; then
        write_state success "$DURATION" "$EXCLUDED"
        if [ "$EXCLUDED" -gt 0 ]; then
            log "end: success duration=${DURATION}s (attempt $ATTEMPT, limited: $EXCLUDED exclusions)"
            [ "$DO_NOTIFY" = "true" ] && notify "Limited backup completed ($EXCLUDED excluded paths)"
        else
            log "end: success duration=${DURATION}s (attempt $ATTEMPT)"
            [ "$DO_NOTIFY" = "true" ] && notify "Backup completed in ${DURATION}s"
        fi
        break
    fi

    # Time Machine scrive RESULT qualche secondo dopo la fine del run: un ritentativo.
    RESULT_CODE="$(backup_result)"
    if [ -z "$RESULT_CODE" ]; then
        /bin/sleep 5
        RESULT_CODE="$(backup_result)"
    fi
    REASON="$(result_reason "$RESULT_CODE")"
    [ "$RC" -ne 0 ] && REASON="tmutil rc=$RC / $REASON"
    write_state failed "$DURATION" "$EXCLUDED"
    log "end: failed $REASON duration=${DURATION}s (attempt $ATTEMPT, snapshot before='$BEFORE' after='$AFTER')"

    # Un solo ritentativo, e solo a sessione bloccata. Se il fallimento ha prodotto
    # percorsi inaccessibili si riprova subito con quelli esclusi; altrimenti (montaggio
    # caduto, errore transitorio) si riprova dopo una pausa, senza esclusioni.
    if [ "$ATTEMPT" -lt 2 ] && [ "$SESSION" = "locked" ]; then
        if [ "$LEARNED_ENABLED" = "true" ] && learn_from_failure "$ATTEMPT_START"; then
            ATTEMPT=2
            log "retry: second attempt with the learned exclusions"
            continue
        fi
        log "retry: nothing to learn, second attempt in 2 minutes"
        ATTEMPT=2
        /bin/sleep 120
        continue
    fi

    [ "$DO_NOTIFY" = "true" ] && notify "Backup failed: $REASON"
    break
done
