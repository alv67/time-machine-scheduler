## Time Machine Scheduler

Pianifica i backup di Time Machine a giorni e orari precisi.

### Italiano

- Requisiti: macOS 14 o successivo, Apple Silicon.
- Scarica il DMG, aprilo e trascina l'app in **Applications**.
- L'app **non è notarizzata**: se macOS la blocca, usa
  **Impostazioni di Sistema → Privacy e Sicurezza → Apri comunque** oppure:
  `xattr -dr com.apple.quarantine /Applications/TimeMachineScheduler.app`.
- Il daemon si installa dall'app con **Salva pianificazione** (password admin).
- Per disinstallare: **Ripristina…** nell'app, poi elimina l'app.
- Verifica i download con `SHA256SUMS.txt`.

### English

- Requirements: macOS 14 or later, Apple Silicon.
- Download the DMG, open it and drag the app into **Applications**.
- This app is **not notarized**: if macOS blocks it, use
  **System Settings → Privacy & Security → Open Anyway** or run:
  `xattr -dr com.apple.quarantine /Applications/TimeMachineScheduler.app`.
- The daemon is installed from the app with **Save schedule** (admin password).
- To uninstall: **Restore…** in the app, then delete the app.
- Verify downloads with `SHA256SUMS.txt`.

---

License: MIT — © 2026 Alessandro Varesi.
