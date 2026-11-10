# Time Machine Scheduler 0.1.0

First public release.

Time Machine Scheduler lets you run Time Machine backups on specific days and
times, instead of relying on the interval anchored to the last completed backup.

## Highlights

- Schedule with configurable time and weekdays.
- Enable/disable toggle and **Back up now**.
- Skips when the destination is unreachable, the Mac is on battery, or a backup is
  already running.
- Prevents idle sleep during the backup and notifies you when it ends.
- Shows Time Machine status, last and next backup, and a readable rotating log.
- Clean restore: removes the daemon and puts Time Machine back on the frequency you
  choose.
- Italian and English UI.

## Install

1. Download `TimeMachineScheduler-0.1.0.dmg` and open it.
2. Drag **TimeMachineScheduler.app** into Applications.
3. Open the app and click **Save schedule** (admin password required).

Requirements: macOS 14+, Apple Silicon, a configured Time Machine destination.

### Gatekeeper

The app is ad-hoc signed and not notarized. If macOS blocks it, use **System
Settings → Privacy & Security → Open Anyway**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/TimeMachineScheduler.app
```

The DMG includes a readme with the same instructions.

## Known limitations

- A powered-off Mac cannot be woken (Apple Silicon has no `poweron`).
- arm64 only; Intel Macs are not supported in this release.
- `caffeinate` does not prevent sleep with the lid closed; the job may start late or
  be unreliable.
- The app only needs to be open to use it; the daemon runs on its own.
- Time Machine should be set to "Manually" to avoid duplicate backups; the app warns
  you when it is not.

## Verify downloads

Use `SHA256SUMS.txt` attached to this release.
