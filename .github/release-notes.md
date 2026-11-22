# Time Machine Scheduler 0.2.0

Nightly backups that survive a locked screen. The headline scenario — lock the
Mac, let it sleep, it wakes for the scheduled time and publishes — is verified
end to end on macOS 27.2 with the device locked.

## Highlights since 0.1.0

- **Swift daemon** replaces the shell job: it holds a power assertion, arms a
  `pmset` wake two minutes before the scheduled time, skips the run when nobody
  is logged in, and logs missed runs when the Mac slept through them.
- **Honest outcomes**: `tmutil startbackup --block` exits 0 even when the backup
  fails, so the result is decided by what the destination really contains,
  detected while the run is still going.
- **Standby support**: with "Prevent the Mac from going to sleep" off, the
  daemon holds a power assertion only in the armed-wake window, because a
  DarkWake goes back to sleep in under a minute; and a Mac that wakes still
  inside the due window runs its backup instead of being reported missed.
- **Learned exclusions** (opt-in): a locked screen no longer loses the night.
  The paths Time Machine cannot read are learned from the failed run, grouped
  to the `Library` of each account plus `/private/var/folders`, and excluded
  only for the next run; the backup publishes as *limited* and the original
  exclusions are restored. Every write is verified by reading the preference
  back, and a denied write is reported, never assumed.
- **Full Disk Access probe**: writing Time Machine's exclusions is a protected
  operation, so the daemon needs Full Disk Access once — the same protection
  `sshd` is subject to. The app shows a red banner with a direct link when the
  grant is missing, and clears it on its own once granted.
- Italian and English UI.

## Install

1. Download `TimeMachineScheduler-0.2.0.dmg` and open it.
2. Drag **TimeMachineScheduler.app** into Applications.
3. Open the app and click **Save schedule** (admin password required).
4. If you enable "Exclude unreachable paths during the backup", grant Full Disk
   Access to `/usr/local/bin/tmscheduler-daemon` when the app asks for it.

Requirements: macOS 14+, Apple Silicon, a configured Time Machine destination.

### Gatekeeper

The app is ad-hoc signed and not notarized. If macOS blocks it, use **System
Settings → Privacy & Security → Open Anyway**, or clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/TimeMachineScheduler.app
```

Note for the daemon's Full Disk Access grant: with an ad-hoc signature the
grant is tied to the exact binary and must be re-granted after every update.
A notarized, Developer-ID build will keep it stable across releases.
