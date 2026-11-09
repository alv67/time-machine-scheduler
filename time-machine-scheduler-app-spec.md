# Specifica — Mini app macOS per pianificare Time Machine

Documento di progetto per la creazione di una piccola applicazione macOS che permetta di
governare **quando** parte Time Machine, con le stesse logiche verificate sul campo nel
novembre 2026 su un MacBook Pro M1 Pro con macOS 27.2.

> **Come usare questo file:** apri un nuovo progetto, allega o indica questo documento
> all'agente e chiedi di implementare l'applicazione seguendo la specifica. La sezione 12
> contiene un prompt pronto.

---

## 1. Contesto e problema

Time Machine su macOS 27 offre solo quattro frequenze: **Ogni ora / Ogni giorno / Ogni
settimana / Manualmente** (chiave `AutoBackupInterval` in
`/Library/Preferences/com.apple.TimeMachine`: 3600, 86400, 604800, oppure assente con
`AutoBackup = 0`).

Limiti riscontrati:

- **Nessun orario fisso.** La frequenza giornaliera è ancorata all'ultimo backup
  completato: se finisce alle 20:25, il successivo parte alle 20:25 del giorno dopo.
  Impossibile dire "sempre alle 02:00".
- **Il backup può partire in un momento sbagliato** (es. mentre il Mac è in Wi-Fi e sta
  per essere messo sul cavo), causando interruzioni e backup incompleti.
- **Rumore**: il NAS è in sala; i backup diurni sono fastidiosi.
- **Il Mac Apple Silicon non si accende da spento** (`pmset -g cap` non espone
  `poweron`): nessuna schedulazione può svegliare un Mac spento.
- **`caffeinate` non impedisce il sonno da coperchio chiuso**: impedisce solo il sonno
  per inattività.

L'app deve risolvere i primi tre punti, e gestire con consapevolezza gli ultimi due.

### Cosa è già stato verificato (non serve ri-verificare)

| Fatto | Verifica |
|---|---|
| macOS 27.2, MacBookPro18,3, Apple M1 Pro | `sw_vers`, `sysctl hw.model` |
| `AutoBackup = 1`, `AutoBackupInterval = 86400` | `defaults read /Library/Preferences/com.apple.TimeMachine` |
| `pmset -g cap` **senza** `poweron` | output del comando |
| `caffeinate` nativo Apple (`com.apple.caffeinate`) | `codesign -dv /usr/bin/caffeinate` |
| `tmutil startbackup --auto` è il meccanismo supportato per scheduler esterni | `man tmutil` |
| TimeMachineEditor 5.2.2 (feb 2023) non aggiornata | sito ufficiale |
| `tmutil listbackups` richiede Accesso completo al disco | errore TCC |
| Destinazione TM: SMB `smb://timemachine@<NAS>/Backup`, quota 2 TB | `tmutil destinationinfo` |
| NAS: `192.168.1.251`, share `Backup`, bundle ~610 GB | verifica diretta |

---

## 2. Obiettivo

Una app **menu bar** (o finestra singola, vedi §4) che permetta di:

1. scegliere **giorni e ora** in cui Time Machine deve partire;
2. abilitare/disabilitare la pianificazione con un interruttore;
3. vedere **stato** (ultimo backup, prossimo previsto, fase corrente);
4. lanciare un backup **adesso**;
5. consultare il **log** delle esecuzioni;
6. tornare in ogni momento alla configurazione standard di macOS.

Non deve reimplementare Time Machine: usa `tmutil`.

---

## 3. Requisiti funzionali

### 3.1 Must

| ID | Requisito |
|---|---|
| F1 | Pianificazione con **ora e minuti** configurabili |
| F2 | Selezione dei **giorni della settimana** (default: tutti) |
| F3 | Interruttore **attiva/disattiva** la pianificazione |
| F4 | Il backup parte tramite `tmutil startbackup --auto --block` |
| F5 | Durante il backup il Mac non deve andare in sonno per inattività (`caffeinate -i`) |
| F6 | Verifica preliminare che il NAS sia raggiungibile (ICMP o TCP 445) con timeout breve; se non lo è, **salta** e registra il motivo |
| F7 | Log persistente con: data/ora, esito, durata, byte/pct se disponibili, motivo dello skip |
| F8 | Pulsante **Backup ora** (esegue immediatamente, fuori pianificazione) |
| F9 | Indicatore dello **stato di Time Machine** (`tmutil status`: Idle / FindingChanges / Copying / HealthCheckFsck / Stopping) |
| F10 | Avviso chiaro se la frequenza di Time Machine **non** è su "Manualmente" |
| F11 | Funzione **Ripristina impostazioni**: rimuove scheduler e riporta TM alla frequenza scelta (default: giornaliera) |

### 3.2 Should

| ID | Requisito |
|---|---|
| S1 | Notifica di sistema a fine backup (riuscito/fallito) |
| S2 | Opzione "salta se il Mac è su batteria" |
| S3 | Opzione "salta se la destinazione non è montabile" |
| S4 | Mostra il prossimo backup previsto in forma leggibile ("domani alle 02:00") |
| S5 | Apertura del log in Console/TextEdit |
| S6 | Icona menu bar con stato sintetico |

### 3.3 Non-obiettivi

- Sostituire Time Machine o gestire più destinazioni.
- Accendere il Mac da spento (impossibile su Apple Silicon).
- Impedire il sonno da coperchio chiuso (non affidabile; meglio documentarlo).
- Backup su cloud, versioning, restore: si usa Time Machine.

---

## 4. Interfaccia

### 4.1 Finestra principale

```
┌──────────────────────────────────────────────────────────┐
│  Time Machine Scheduler                          [⚙︎]     │
│                                                          │
│  ● Pianificazione attiva                         [ ON ]  │
│                                                          │
│  Ora di avvio      [ 02:00 ]                             │
│  Giorni            [✓] Lun [✓] Mar [✓] Mer [✓] Gio       │
│                    [✓] Ven [✓] Sab [✓] Dom               │
│                                                          │
│  Opzioni                                                 │
│    [✓] Avvia solo se il NAS è raggiungibile              │
│    [✓] Impedisci il sonno durante il backup              │
│    [ ] Salta se il Mac è a batteria                      │
│    [✓] Notifica a fine backup                            │
│                                                          │
│  ──────────────────────────────────────────────────────  │
│  Ultimo backup     9 nov 2026, 20:25 · riuscito · 16 GB  │
│  Prossimo backup   dom 10 nov, 02:00                     │
│  Stato Time Machine  Inattivo                            │
│                                                          │
│  [ Backup ora ]   [ Apri log ]   [ Ripristina… ]         │
└──────────────────────────────────────────────────────────┘
```

### 4.2 Banner di avviso

Se `AutoBackup != 0` (frequenza non manuale):

```
⚠︎ Time Machine ha una frequenza automatica attiva (ogni giorno).
   Lo scheduler funziona meglio con frequenza "Manualmente".
   [ Imposta su Manualmente ]
```

### 4.3 Menu bar (opzionale)

Icona con menu: stato, prossimo backup, "Backup ora", "Apri app", "Disattiva fino a domani".

---

## 5. Architettura tecnica

### 5.1 Componenti

```
TimeMachineScheduler.app
├── App (SwiftUI)                 ← UI, scrittura config, stato
├── Content/Library/LaunchDaemons/
│   └── local.tmscheduler.nightly.plist   ← daemon schedulato
├── Content/MacOS/tmscheduler-run          ← eseguibile/script del daemon
└── Content/Resources/…

/Library/Application Support/TMScheduler/
├── config.json                   ← configurazione (scritta dall'app)
├── last-run.json                 ← stato ultima esecuzione (scritto dal daemon)
└── tmscheduler.log               ← log
```

### 5.2 Perché un LaunchDaemon e non un LaunchAgent

Il daemon gira come root e **funziona anche con sessione bloccata o utente non loggato**.
Un LaunchAgent richiede una sessione grafica attiva.

### 5.3 Modello di configurazione (`config.json`)

```json
{
  "enabled": true,
  "hour": 2,
  "minute": 0,
  "weekdays": [1, 2, 3, 4, 5, 6, 7],
  "requireHost": "192.168.1.251",
  "requireNAS": true,
  "preventSleep": true,
  "skipOnBattery": false,
  "notify": true,
  "version": 1
}
```

`weekdays`: 1 = lunedì … 7 = domenica (ISO-8601).

### 5.4 Comportamento del daemon

Pseudocodice:

```text
leggi config.json
se !enabled → esci
se oggi non è in weekdays → esci
se last-run.date == oggi → esci            # evita doppie esecuzioni
se skipOnBattery e pmset -g batt è "Battery Power" → log e esci
se requireNAS e host non raggiungibile (timeout 3 s) → log e esci
se una sessione TM è già in corso (tmutil status Running=1) → esci
log "start"
caffeinate -i tmutil startbackup --auto --block
leggi tmutil status per esito/durata
scrivi last-run.json
log "end: <esito> <durata>"
notifica (se abilitata)
```

### 5.5 Installazione del daemon: due approcci

**A. Pragmatico (consigliato per uso personale)**

L'app scrive plist e script in una cartella temporanea e li installa con:

```bash
osascript -e 'do shell script "..." with administrator privileges'
```

Vantaggi: nessun helper privilegiato, nessuna firma particolare, ~30 righe di codice.
Svantaggi: prompt di password admin a ogni modifica della pianificazione.

**B. Corretto (SMAppService)**

- plist e daemon dentro il bundle;
- `SMAppService.daemon(plistName: "local.tmscheduler.nightly.plist").register()`;
- l'utente approva in Impostazioni → Generali → Elementi login;
- l'app deve essere firmata (anche ad-hoc per uso locale).

Vantaggi: nessuna password, gestione pulita. Svantaggi: più codice, vincoli di firma e
di percorso (`/Applications`).

> Per una mini-app personale suggerisco **A**, con la possibilità di migrare a B in
> seguito.

### 5.6 Aggiornamento della pianificazione

Con `StartCalendarInterval` statico nel plist, cambiare ora/giorni richiede:

```bash
launchctl bootout system /Library/LaunchDaemons/local.tmscheduler.nightly.plist
# riscrivi il plist
launchctl bootstrap system /Library/LaunchDaemons/local.tmscheduler.nightly.plist
```

Alternativa più semplice: **una sola voce `StartCalendarInterval` per ogni giorno
selezionato** (array di dict), rigenerata dal plist.

In alternativa, un `StartInterval` di 300 secondi e la logica "è ora?" dentro lo script:
meno preciso ma l'app deve solo scrivere il JSON. Sconsigliato se serve puntualità.

### 5.7 Interazione con le preferenze di Time Machine

Lettura (senza privilegi):

```bash
defaults read /Library/Preferences/com.apple.TimeMachine AutoBackup
defaults read /Library/Preferences/com.apple.TimeMachine AutoBackupInterval
```

Impostazione su "Manualmente" (con privilegi):

```bash
sudo defaults write /Library/Preferences/com.apple.TimeMachine AutoBackup -bool false
sudo killall backupd     # facoltativo, per applicare subito
```

Ripristino (default: giornaliero):

```bash
sudo defaults write /Library/Preferences/com.apple.TimeMachine AutoBackup -bool true
sudo defaults write /Library/Preferences/com.apple.TimeMachine AutoBackupInterval -int 86400
sudo killall backupd
```

### 5.8 Lettura dello stato

```bash
tmutil status            # output plist-like: BackupPhase, Running, Percent, bytes
tmutil latestbackup      # richiede Accesso completo al disco per il terminale
tmutil destinationinfo   # destinazione e quota
```

Per l'app: usare `Process` + parsing dell'output, oppure
`tmutil status -X` se disponibile (verificare: su alcune versioni restituisce XML).

> **Nota TCC:** le API che leggono `tmutil listbackups` richiedono *Accesso completo al
> disco*. L'app deve gestire l'errore e mostrare un link a Impostazioni → Privacy.

---

## 6. Casi limite e comportamento atteso

| Caso | Comportamento |
|---|---|
| Mac spento alle 02:00 | Nessuna esecuzione. Il backup avverrà al prossimo avvio (Time Machine recupera). L'app lo documenta nella UI |
| Mac in sonno, coperchio aperto | Il daemon non parte finché il Mac dorme; al risveglio macOS esegue il job in ritardo. Opzionale: `pmset schedule wake` |
| Mac in sonno, coperchio chiuso | Idem, ma il Mac torna in sonno; backup non affidabile. Documentato |
| NAS non raggiungibile | Skip con motivo nel log; nessun backup a metà |
| Backup già in corso | Skip (evita doppie sessioni) |
| Destinazione non montata | Time Machine la monta da sola; se fallisce, esito negativo nel log |
| Utente cambia l'ora nel frattempo | Il plist viene rigenerato; `launchd` ricarica |
| Frequenza TM non manuale | Banner di avviso + pulsante per correggere |

---

## 7. Log e diagnostica

Formato consigliato (una riga JSON per evento, più una versione leggibile):

```json
{"ts":"2026-11-10T02:00:03+01:00","event":"start","phase":"FindingChanges"}
{"ts":"2026-11-10T02:14:22+01:00","event":"end","result":"success","duration_s":859,"bytes":16106127360}
```

- rotazione a 1 MB, 3 file;
- l'app mostra le ultime 200 righe con colori (verde/rosso/giallo);
- pulsante "Apri log nel Finder".

---

## 8. Piano di test

1. **Installazione**: l'app installa plist e script; `launchctl print system/local.tmscheduler.nightly` mostra il job.
2. **Esecuzione manuale**: `sudo launchctl kickstart -k system/local.tmscheduler.nightly` → il backup parte e il log registra inizio/fine.
3. **Skip per host**: impostare un IP inesistente → log "host unreachable", nessun backup.
4. **Skip per backup in corso**: avviare un backup e poi il daemon → skip.
5. **Cambio orario**: modificare l'ora dall'app → verificare che il plist cambi e il job venga ricaricato.
6. **Disattivazione**: interruttore OFF → il job non parte.
7. **Ripristino**: "Ripristina" → plist rimosso, `AutoBackup` e `AutoBackupInterval` riportati ai valori scelti.
8. **Sonno**: Mac in sonno coperchio aperto alle 02:00 → comportamento documentato e coerente.
9. **Nessuna regressione**: dopo l'uso, `tmutil listbackups` continua a funzionare e i backup manuali da UI di sistema funzionano.

---

## 9. Struttura del progetto Xcode

```
TimeMachineScheduler/
├── TimeMachineScheduler.xcodeproj
├── App/
│   ├── TimeMachineSchedulerApp.swift
│   ├── ContentView.swift
│   ├── SettingsView.swift
│   ├── StatusModel.swift
│   ├── SchedulerInstaller.swift      ← approccio A (osascript) o B (SMAppService)
│   └── TMController.swift            ← wrapper su tmutil
├── Daemon/
│   ├── local.tmscheduler.nightly.plist
│   └── tmscheduler-run.sh
└── Tests/
```

Target: **macOS 14+**, SwiftUI, nessuna dipendenza esterna. App non sandboxed (deve
eseguire `tmutil` e installare un daemon).

---

## 10. Criteri di accettazione

- [ ] Con pianificazione attiva alle 02:00 e Mac sveglio, il backup parte entro 60 secondi.
- [ ] Con il NAS spento, il daemon salta e lo scrive nel log, senza avviare Time Machine.
- [ ] L'app mostra lo stato di Time Machine e l'ultimo backup completato.
- [ ] "Ripristina" lascia il sistema come prima dell'installazione.
- [ ] Nessun file fuori da `/Library/Application Support/TMScheduler`,
      `/Library/LaunchDaemons/local.tmscheduler.nightly.plist`, `/usr/local/bin/tmscheduler-run`.
- [ ] Il log è leggibile e ruota.

---

## 11. Riferimento: script e plist funzionanti

Questi sono i file che l'app deve generare. Sono già stati validati a mano.

### `tmscheduler-run.sh`

```bash
#!/bin/bash
set -uo pipefail

CONF="/Library/Application Support/TMScheduler/config.json"
LOG="/Library/Application Support/TMScheduler/tmscheduler.log"
STATE="/Library/Application Support/TMScheduler/last-run.json"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

jget() { /usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$CONF" "$1"; }

[ -f "$CONF" ] || { log "config mancante"; exit 0; }

[ "$(jget enabled)" = "True" ] || exit 0

REQ=$(jget requireNAS)
HOST=$(jget requireHost)

if [ "$REQ" = "True" ] && ! /sbin/ping -c1 -t2 "$HOST" >/dev/null 2>&1; then
    log "skip: host $HOST non raggiungibile"
    exit 0
fi

if /usr/bin/tmutil status 2>/dev/null | /usr/bin/grep -q 'Running = 1'; then
    log "skip: backup già in corso"
    exit 0
fi

log "start"
START=$(/bin/date +%s)
/usr/bin/caffeinate -i /usr/bin/tmutil startbackup --auto --block
RC=$?
END=$(/bin/date +%s)
log "end: rc=$RC durata=$((END-START))s"
```

### `local.tmscheduler.nightly.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>local.tmscheduler.nightly</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/usr/local/bin/tmscheduler-run</string>
  </array>
  <key>StartCalendarInterval</key>
  <array>
    <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>2</integer><key>Minute</key><integer>0</integer></dict>
    <!-- una voce per ogni giorno selezionato: Weekday 1=lun ... 7=dom -->
  </array>
  <key>RunAtLoad</key><false/>
  <key>StandardErrorPath</key><string>/var/log/tmscheduler.err</string>
</dict>
</plist>
```

> `Weekday` in `StartCalendarInterval` usa 0=domenica … 6=sabato (convenzione
> `tm_wday`), **diversa** da ISO-8601 usata nel config. La conversione va fatta
> nell'app: ISO 7 (domenica) → `Weekday 0`.

---

## 12. Prompt suggerito per il nuovo progetto

```text
Leggi il file time-machine-scheduler-app-spec.md e implementa l'applicazione
descritta, seguendo la specifica alla lettera.

Vincoli:
- macOS 14+, SwiftUI, nessuna dipendenza esterna, app non sandboxed
- approccio A per l'installazione del daemon (osascript con privilegi admin)
- non modificare nulla fuori dai percorsi elencati nella sezione 10
- includi i test manuali della sezione 8 come checklist nel README

Parti dalla sezione 11: script e plist devono essere generati esattamente come
descritto, poi costruisci la UI e il controller.
```

---

## 13. Note finali

- Il Mac è un **Apple Silicon**: non si accende da spento. Qualsiasi promessa contraria
  nella UI sarebbe falsa.
- `caffeinate` non impedisce il sonno da coperchio chiuso: l'app lo deve dire, non
  simulare.
- La frequenza "Manualmente" è il presupposto per evitare backup doppi: l'app deve
  verificarla e proporre la correzione, non imporla silenziosamente.
- Time Machine è di Apple: qualunque soluzione che ne tocchi gli interni va trattata con
  diffidenza. Questo progetto usa solo `tmutil` e `launchd`, API documentate.
