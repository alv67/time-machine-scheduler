<div align="center">

<img src="docs/assets/icon.png" width="88" alt="Icona di Time Machine Scheduler" />

# Time Machine Scheduler

**I backup quando decidi tu.**

App macOS per pianificare l'avvio dei backup di Time Machine a giorni e orari
precisi, invece di affidarti alla frequenza ancorata all'ultimo backup.

[![Download DMG](https://img.shields.io/badge/download-DMG-blue?style=flat-square)](https://github.com/alv67/time-machine-scheduler/releases/latest)
[![Version](https://img.shields.io/badge/version-0.1.0-blue?style=flat-square)](https://github.com/alv67/time-machine-scheduler/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white&style=flat-square)](https://www.apple.com/macos/)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-000000?style=flat-square)](https://support.apple.com/en-us/102861)
[![SwiftUI](https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white&style=flat-square)](https://developer.apple.com/xcode/swiftui/)

[**Download**](https://github.com/alv67/time-machine-scheduler/releases/latest) · [**Releases**](https://github.com/alv67/time-machine-scheduler/releases) · [**Issues**](https://github.com/alv67/time-machine-scheduler/issues) · [**Offrimi un caffè**](https://buymeacoffee.com/alv67)

</div>

Time Machine decide quando fare i backup in base all'ultimo completato. Time Machine
Scheduler aggiunge una pianificazione vera: ora, minuti e giorni della settimana.
Implementata secondo `time-machine-scheduler-app-spec.md`: macOS 14+, SwiftUI,
nessuna dipendenza esterna, app non sandboxed, daemon `launchd` installato con
`osascript` e privilegi admin (approccio A).

## Funzionalità

- **Orario e giorni** — scegli l'ora esatta e i giorni della settimana; il backup parte quando decidi tu.
- **La tua destinazione** — legge la destinazione configurata in Time Machine, locale o di rete, e verifica che sia raggiungibile.
- **Backup senza sorprese** — salta se il Mac è a batteria, impedisce il sonno durante il backup e avvisa a fine operazione.
- **Stato e log** — fase, percentuale, ultimo backup e log leggibile con rotazione automatica.
- **Backup ora** — avvia subito un backup fuori pianificazione, senza aspettare l'orario previsto.
- **Ripristino pulito** — rimuove daemon, script e log e riporta Time Machine alla frequenza scelta.
- **Italiano e inglese** — interfaccia, guida e pannello About seguono la lingua di sistema.

## Requisiti

- macOS 14 o successivo
- Mac con Apple Silicon (build arm64)
- Una destinazione Time Machine configurata
- Password di amministratore per installare il daemon
- Command Line Tools per compilare (`xcode-select --install`); nessun progetto Xcode richiesto

## Installazione

1. Scarica il DMG e aprilo.
2. Trascina **TimeMachineScheduler.app** nella cartella Applications.
3. Apri l'app e premi **Salva pianificazione**: installa il daemon e richiede la password di amministratore.

### Gatekeeper

L'app è firmata ad-hoc, non con un Developer ID e non è notarizzata. Su macOS
recente il doppio clic sul DMG può mostrare «Installazione non riuscita» perché
l'installazione automatica richiede una firma verificabile.

Se macOS blocca l'app, usa **Impostazioni di Sistema → Privacy e Sicurezza → Apri
comunque** oppure togli la quarantena:

```bash
xattr -dr com.apple.quarantine /Applications/TimeMachineScheduler.app
```

Installazione locale senza Gatekeeper:

```bash
make install
# oppure in una cartella utente:
make install PREFIX=~/Applications
```

## Uso

1. Imposta ora, giorni e opzioni.
2. **Salva pianificazione**: chiede la password admin e installa/aggiorna il daemon.
3. Se il banner segnala una frequenza automatica di Time Machine, usa
   **Apri Impostazioni Time Machine** e scegli «Manualmente» per evitare backup doppi.
4. **Backup ora** avvia un backup fuori pianificazione.
5. **Ripristina…** rimuove daemon, script e log e riporta Time Machine alla
   frequenza scelta (Manualmente, ogni ora, ogni giorno, ogni settimana).

La destinazione non va inserita a mano: viene letta da Time Machine
(`tmutil destinationinfo`) e funziona con qualsiasi destinazione, locale o di rete.
Con la verifica di raggiungibilità attiva, il daemon controlla l'host della
destinazione di rete (anche i nomi Bonjour `*.local`) prima di avviare il backup.

## Build da sorgente

```bash
make test     # verifica la logica di pianificazione e la generazione del plist
make app      # crea build/TimeMachineScheduler.app
make run      # apre l'app
make dmg      # crea build/TimeMachineScheduler-0.1.0.dmg
make release  # crea DMG, ZIP e SHA256SUMS.txt
make install  # copia in /Applications e toglie la quarantena
```

Il build predefinito è **arm64**. Per un binario universale (Intel su macOS 14–26,
non testato su hardware Intel):

```bash
make release ARCHS="arm64 x86_64"
```

Per firmare con un Developer ID:

```bash
make release SIGN_ID="Developer ID Application: Nome (TEAMID)"
```

Se dopo una modifica dell'icona il Dock mostra ancora quella vecchia, macOS sta
usando la cache di LaunchServices:

```bash
make refresh-icon
```

## Stack

| Componente | Tecnologia |
|------------|------------|
| App | SwiftUI, macOS 14+, arm64 |
| Daemon | `launchd` + script shell, installato da `osascript` con privilegi admin |
| Build | `swiftc` + `Makefile`, nessun progetto Xcode |
| Test | Swift, logica di pianificazione e generazione del plist |
| Distribuzione | DMG, ZIP, `SHA256SUMS.txt`, GitHub Actions |

## Struttura

```
App/        UI SwiftUI, modello, controller tmutil, installer
Daemon/     script eseguito dal LaunchDaemon
Resources/  icona, localizzazioni it/en e Leggimi per il DMG
docs/       pagina web del progetto (IT/EN) per GitHub Pages
Tools/      generatore dell'icona (Core Graphics)
Tests/      test della logica pura (pianificazione + plist)
.github/    workflow di release, Pages e triage
Info.plist  metadati del bundle
Makefile    build, test, run, dmg, release
```

L'icona è generata da `Tools/make-icon.swift` (nessun file binario esterno da
scaricare); `make icon` la rigenera. Il menu dell'app contiene **Informazioni su
Time Machine Scheduler** (versione, copyright © 2026 Alessandro Varesi e link al
progetto). Il menu **Aiuto** apre una guida locale in una finestra dedicata; la
pagina GitHub resta raggiungibile da Aiuto e da About.

## Limiti noti

- Mac spento: nessuna schedulazione può accenderlo (Apple Silicon non supporta
  `poweron`). Il backup avverrà al successivo avvio.
- Build solo arm64: i Mac Intel non sono supportati in questa release.
- Mac in sonno con coperchio chiuso: `caffeinate` non impedisce quel tipo di sonno;
  il job può partire in ritardo o non essere affidabile.
- La UI deve restare aperta solo per usarla: il daemon lavora in autonomia.
- Icona/menu nella barra dei menu non inclusa (sezione 4.3 facoltativa).
- `tmutil listbackups` non viene usato: nessun permesso di Accesso completo al disco
  richiesto.

## Release

`make release` produce il DMG (app, collegamento Applications e `Leggimi.txt`
IT/EN), lo ZIP e `SHA256SUMS.txt`. La release pubblica si crea con un tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Il workflow `.github/workflows/release.yml` esegue i test, crea gli artefatti e
pubblica la release su GitHub. Il tag deve coincidere con
`CFBundleShortVersionString` in `Info.plist`.

Senza notarizzazione la release resta “non verificata” da Gatekeeper: il DMG
contiene le istruzioni, ma gli utenti devono autorizzare l'app. Un eventuale tap
Homebrew può essere aggiunto dopo, puntando al DMG della release.

<details>
<summary><b>Flusso di release e sito web</b></summary>

Flusso: sviluppo su `develop`, preparazione su `release/0.1.0`, pull request verso
`main` quando la release è pronta, merge su `main` → pubblicazione della pagina
GitHub Pages, tag `v0.1.0` → release GitHub.

La pagina del progetto è in `docs/` (italiano in `docs/index.html`, inglese in
`docs/en/index.html`) e viene pubblicata dal workflow
`.github/workflows/pages.yml` quando si aggiorna `main`.

- URL previsto: https://alv67.github.io/time-machine-scheduler/
- GitHub Pages su un repository privato richiede GitHub Pro/Team/Enterprise. Con
  GitHub Free il repository deve essere pubblico.

</details>

<details>
<summary><b>Percorsi di sistema toccati</b></summary>

- `/Library/Application Support/TMScheduler/config.json`
- `/Library/Application Support/TMScheduler/last-run.json`
- `/Library/Application Support/TMScheduler/tmscheduler.log` (+ `.1`, `.2`, `.3`)
- `/Library/LaunchDaemons/local.tmscheduler.nightly.plist`
- `/usr/local/bin/tmscheduler-run`
- preferenze `AutoBackup` / `AutoBackupInterval` di Time Machine (solo tramite
  "Apri Impostazioni Time Machine" e "Ripristina…")

</details>

<details>
<summary><b>Test manuali (specifica §8)</b></summary>

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

</details>

## Supporto

Se l'app ti è utile, puoi [offrirmi un caffè](https://buymeacoffee.com/alv67).
Il progetto resta gratuito e open source per tutti.

## Licenza

MIT — vedi [LICENSE](LICENSE). © 2026 Alessandro Varesi.
