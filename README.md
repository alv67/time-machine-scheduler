# Time Machine Scheduler

Mini app macOS per pianificare l'avvio dei backup di Time Machine a giorni e orari
precisi, invece di affidarsi alla frequenza ancorata all'ultimo backup.

Implementata secondo `time-machine-scheduler-app-spec.md`: macOS 14+, SwiftUI,
nessuna dipendenza esterna, app non sandboxed, daemon `launchd` installato con
`osascript` e privilegi admin (approccio A).

## Requisiti

- macOS 14 o successivo
- Command Line Tools (`xcode-select --install`)
- Nessun progetto Xcode richiesto: la build usa `swiftc` e un `Makefile`

## Build e avvio

```bash
make test   # verifica la logica di pianificazione e la generazione del plist
make app    # crea build/TimeMachineScheduler.app
make run    # apre l'app
make dmg    # crea build/TimeMachineScheduler-1.0.dmg
make install  # copia in /Applications e toglie la quarantena
```

Se dopo una modifica dell'icona il Dock mostra ancora quella vecchia, macOS sta
usando la cache di LaunchServices:

```bash
make refresh-icon
```

Il DMG contiene l'app e il collegamento alla cartella **Applications**: si apre,
si trascina l'app e si espelle il disco.

### Gatekeeper

L'app è firmata ad-hoc, non con un Developer ID e non è notarizzata. Su macOS
recente il doppio clic sul DMG può mostrare «Installazione non riuscita» perché
l'installazione automatica richiede una firma verificabile.

Installazione locale senza Gatekeeper:

```bash
make install
# oppure in una cartella utente:
make install PREFIX=~/Applications
```

Se il DMG è stato scaricato, togli la quarantena prima di aprirlo:

```bash
xattr -d com.apple.quarantine ~/Downloads/TimeMachineScheduler-1.0.dmg
```

Per un DMG apribile con doppio clic su altri Mac serve una firma **Developer ID
Application** e la notarizzazione Apple; con il solo certificato Apple Development
Gatekeeper rifiuta comunque l'app.

L'app può essere trascinata in `/Applications`. Per rimuoverla basta cancellarla:
la configurazione di sistema si toglie dal pulsante **Ripristina…**.

## Uso

1. Imposta ora, giorni e opzioni.
2. **Salva pianificazione**: chiede la password admin e installa/aggiorna il daemon.
3. Se il banner segnala una frequenza automatica di Time Machine, usa
   **Apri Impostazioni Time Machine** e scegli «Manualmente» per evitare backup doppi.
4. **Backup ora** avvia un backup fuori pianificazione.
5. **Ripristina…** rimuove daemon, script e log e riporta Time Machine alla
   frequenza scelta (Manualmente, ogni ora, ogni giorno, ogni settimana). Se macOS
   non applica la modifica, l'app apre le Impostazioni e lo segnala.

La destinazione non va inserita a mano: viene letta da Time Machine
(`tmutil destinationinfo`) e funziona con qualsiasi destinazione, locale o di rete.
Con la verifica di raggiungibilità attiva, il daemon controlla l'host della
destinazione di rete (anche i nomi Bonjour `*.local`) prima di avviare il backup.

## Percorsi toccati

Solo questi:

- `/Library/Application Support/TMScheduler/config.json`
- `/Library/Application Support/TMScheduler/last-run.json`
- `/Library/Application Support/TMScheduler/tmscheduler.log` (+ `.1`, `.2`, `.3`)
- `/Library/LaunchDaemons/local.tmscheduler.nightly.plist`
- `/usr/local/bin/tmscheduler-run`
- preferenze `AutoBackup` / `AutoBackupInterval` di Time Machine (solo tramite
  "Apri Impostazioni Time Machine" e "Ripristina…")

## Lingue

L'interfaccia, la guida e il pannello About sono disponibili in **italiano e inglese**
e seguono la lingua di sistema; le altre lingue usano l'inglese. I messaggi tecnici
del daemon (log e notifiche) sono in inglese.

Per aggiungere una lingua: copia `Resources/en.lproj` in `Resources/<codice>.lproj`,
traduci `Localizable.strings` e aggiungi il codice a `CFBundleLocalizations` in
`Info.plist`.

Le modifiche al daemon, compresi i messaggi di log, si applicano premendo di nuovo
**Salva pianificazione**.

## Limiti noti

- Mac spento: nessuna schedulazione può accenderlo (Apple Silicon non supporta
  `poweron`). Il backup avverrà al successivo avvio.
- Mac in sonno con coperchio chiuso: `caffeinate` non impedisce quel tipo di sonno;
  il job può partire in ritardo o non essere affidabile.
- La UI deve restare aperta solo per usarla: il daemon lavora in autonomia.
- Icona/menu nella barra dei menu non inclusa (sezione 4.3 facoltativa).
- `tmutil listbackups` non viene usato: nessun permesso di Accesso completo al disco
  richiesto.

## Test manuali (specifica §8)

- [ ] Dopo **Salva pianificazione**, `launchctl print system/local.tmscheduler.nightly`
      mostra il job.
- [ ] `sudo launchctl kickstart -k system/local.tmscheduler.nightly` avvia il backup
      e il log registra inizio/fine.
- [ ] Con la destinazione Time Machine spenta o irraggiungibile, il daemon scrive
      `skip: destination … unreachable` e non avvia Time Machine.
- [ ] Con un backup già in corso, il daemon scrive `skip: backup already running`.
- [ ] Cambiando ora/giorni dall'app, il plist viene rigenerato e il job ricaricato.
- [ ] Con l'interruttore OFF, il job non parte.
- [ ] **Ripristina…** rimuove plist e script e riporta `AutoBackup`/`AutoBackupInterval`
      ai valori scelti.
- [ ] Mac in sonno con coperchio aperto alle 02:00: comportamento coerente con i limiti
      sopra.
- [ ] Dopo l'uso, `tmutil listbackups` e i backup manuali da UI di sistema funzionano.

## Struttura

```
App/        UI SwiftUI, modello, controller tmutil, installer
Daemon/     script eseguito dal LaunchDaemon
Resources/  icona sorgente e localizzazioni it/en
Tools/      generatore dell'icona (Core Graphics)
Tests/      test della logica pura (pianificazione + plist)
Info.plist  metadati del bundle
Makefile    build, test, run, icon
```

L'icona è generata da `Tools/make-icon.swift` (nessun file binario esterno da
scaricare); `make icon` la rigenera. Il menu dell'app contiene **Informazioni su
Time Machine Scheduler** (versione, copyright © 2026 alv67 e link al progetto).
Il menu **Aiuto** apre una guida locale in una finestra dedicata; la pagina GitHub
resta raggiungibile da Aiuto e da About. L'app usa una finestra principale singola.
