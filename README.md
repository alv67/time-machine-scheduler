<div align="center">

<img src="docs/assets/icon.png" width="88" alt="Time Machine Scheduler icon" />

# Time Machine Scheduler

**Backups on your schedule.**

A macOS app to run Time Machine backups on specific days and times, instead of
relying on the interval anchored to the last completed backup.

[![Download DMG](https://img.shields.io/badge/download-DMG-blue?style=flat-square)](https://github.com/alv67/time-machine-scheduler/releases/latest)
[![Version](https://img.shields.io/badge/version-0.1.0-blue?style=flat-square)](https://github.com/alv67/time-machine-scheduler/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white&style=flat-square)](https://www.apple.com/macos/)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-000000?style=flat-square)](https://support.apple.com/en-us/102861)
[![SwiftUI](https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white&style=flat-square)](https://developer.apple.com/xcode/swiftui/)

[**Download**](https://github.com/alv67/time-machine-scheduler/releases/latest) · [**Releases**](https://github.com/alv67/time-machine-scheduler/releases) · [**Issues**](https://github.com/alv67/time-machine-scheduler/issues) · [**Buy me a coffee**](https://buymeacoffee.com/alv67)

</div>

Time Machine decides when to back up based on the last completed backup. Time
Machine Scheduler adds a real schedule: hour, minute and weekdays. Built with
macOS 14+, SwiftUI, no external dependencies, non-sandboxed app, `launchd` daemon
installed with `osascript` and admin privileges (approach A).

<p align="center">
  <img src="docs/assets/screenshots/en/app.png" width="420" alt="Time Machine Scheduler — schedule, options and status">
  <br>
  <sub><i>Schedule, options, last and next backup, and a readable log in one window.</i></sub>
</p>

## Features

- **Time and days** — pick the exact time and weekdays; the backup runs when you decide.
- **No idle sleep** — optional: keeps the Mac awake so the scheduled time is not missed, while the display can still sleep.
- **Your destination** — reads the destination configured in Time Machine, local or network, and checks that it is reachable.
- **No surprises** — skips on battery, prevents sleep during the backup and notifies you when it ends.
- **No standby** — optional: the daemon keeps the Mac awake so the scheduled time is not missed, while the display can still sleep.
- **Status and logs** — phase, percentage, last backup and a readable log with automatic rotation.
- **Back up now** — start a backup outside the schedule without waiting for the next run.
- **Clean restore** — removes daemon, script and logs and puts Time Machine back on the frequency you choose.
- **Italian and English** — UI, help and About panel follow the system language.

## Requirements

- macOS 14 or later
- Apple Silicon Mac (arm64 build)
- A configured Time Machine destination
- Administrator password to install the daemon
- Command Line Tools to build (`xcode-select --install`); no Xcode project required

## Install

1. Download the DMG and open it.
2. Drag **TimeMachineScheduler.app** into Applications.
3. Open the app and click **Save schedule**: it installs the daemon and asks for the administrator password.

### Gatekeeper

The app is ad-hoc signed, not with a Developer ID, and not notarized. On recent
macOS, double-clicking the DMG may show "Installation failed" because automatic
installation requires a verifiable signature.

If macOS blocks the app, use **System Settings → Privacy & Security → Open
Anyway**, or remove the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/TimeMachineScheduler.app
```

Local install without Gatekeeper:

```bash
make install
# or into a user folder:
make install PREFIX=~/Applications
```

## Usage

1. Set time, days and options.
2. **Save schedule**: asks for the admin password and installs/updates the daemon.
3. If the banner reports an automatic Time Machine frequency, use **Open Time
   Machine Settings** and choose "Manually" to avoid duplicate backups.
4. **Back up now** starts a backup outside the schedule.
5. **Restore…** removes daemon, script and logs and puts Time Machine back on the
   frequency you choose (Manually, hourly, daily, weekly).

The destination is not entered by hand: it is read from Time Machine
(`tmutil destinationinfo`) and works with any destination, local or network. With
reachability checks enabled, the daemon pings the network destination host (including
Bonjour names such as `*.local`) before starting the backup.

## Build from source

```bash
make test     # checks scheduling logic and plist generation
make app      # builds build/TimeMachineScheduler.app
make run      # opens the app
make dmg      # builds build/TimeMachineScheduler-0.1.0.dmg
make release  # builds DMG, ZIP and SHA256SUMS.txt
make install  # copies to /Applications and removes the quarantine flag
```

The default build is **arm64**. For a universal binary (Intel on macOS 14–26, not
tested on Intel hardware):

```bash
make release ARCHS="arm64 x86_64"
```

To sign with a Developer ID:

```bash
make release SIGN_ID="Developer ID Application: Name (TEAMID)"
```

If the Dock still shows the old icon after changing it, macOS is using the
LaunchServices cache:

```bash
make refresh-icon
```

## Stack

| Layer | Technology |
|-------|------------|
| App | SwiftUI, macOS 14+, arm64 |
| Daemon | `launchd` + a Swift binary that prevents idle sleep, arms a wake and starts the backup; installed by `osascript` with admin privileges |
| Build | `swiftc` + `Makefile`, no Xcode project |
| Tests | Swift, scheduling logic and plist generation |
| Distribution | DMG, ZIP, `SHA256SUMS.txt`, GitHub Actions |

## Project layout

```
App/        SwiftUI UI, model, tmutil controller, installer
Daemon/     scheduling daemon (Swift) and the single-backup script it runs
Resources/  icon, it/en localizations and DMG readme
docs/       project website (IT/EN) for GitHub Pages
Tools/      icon generator (Core Graphics)
Tests/      tests for pure logic (schedule + plist)
.github/    release, Pages and triage workflows
Info.plist  bundle metadata
Makefile    build, test, run, dmg, release
```

The icon is generated by `Tools/make-icon.swift` (no external binary to download);
`make icon` regenerates it. The app menu includes **About Time Machine Scheduler**
(version, copyright © 2026 Alessandro Varesi and project link). The **Help** menu
opens a local guide in a dedicated window; the GitHub page is reachable from both
Help and About.

## Known limitations

- Mac powered off: no schedule can wake it (Apple Silicon does not support
  `poweron`). The backup runs on the next boot.
- arm64 only: Intel Macs are not supported in this release.
- Mac asleep with the lid closed: `caffeinate` does not prevent that kind of sleep;
  the job may start late or be unreliable.
- The Mac must be **awake and unlocked** at the scheduled time. Time Machine cannot
  read file-protection class A data (some caches and preferences of every account)
  while the device is locked, and there is no supported way around it: an assertion
  taken by a third-party process has no effect (verified on macOS 27.2), and SSH
  does not unlock the device either. With "Require password after screen saver
  begins or display is turned off" set to a delay longer than the night (or off),
  the display can sleep while the session stays unlocked: the backup then runs with
  the screen off. Trade-off: anyone at the keyboard before the lock kicks in has
  the session.
- A wake is armed two minutes before the scheduled time (`pmset schedule wake`), so
  an idle sleep does not lose the run. A powered-off Mac, or a reboot with nobody
  logged in, still does; a missed run is logged and notified when the Mac wakes.
- A backup skipped because the Mac was off or asleep is not caught up later; the
  next one runs at the next scheduled time.
- "Prevent the Mac from going to sleep" keeps the Mac awake for as long as the
  service is active: more power and heat, and the battery drains on battery
  power. The display can still sleep. A Mac with the lid closed and no external
  display sleeps anyway, and a powered-off Mac cannot be woken by a schedule
  (Apple Silicon).
- The UI only needs to be open to use it: the daemon works on its own.
- Menu bar icon/menu not included.
- `tmutil listbackups` is not used: no Full Disk Access permission required.

## Release

`make release` produces the DMG (app, Applications link and IT/EN `Leggimi.txt`),
the ZIP and `SHA256SUMS.txt`. A public release is created with a tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The `.github/workflows/release.yml` workflow runs the tests, builds the artifacts
and publishes the GitHub release. The tag must match `CFBundleShortVersionString`
in `Info.plist`.

Without notarization the release stays "unverified" by Gatekeeper: the DMG
includes instructions, but users must approve the app. A Homebrew tap can be added
later, pointing at the release DMG.

<details>
<summary><b>Release flow and website</b></summary>

Flow: development on `develop`, preparation on `release/0.1.0`, pull request to
`main` when the release is ready, merge to `main` → GitHub Pages deployment, tag
`v0.1.0` → GitHub release.

The project page lives in `docs/` (Italian in `docs/index.html`, English in
`docs/en/index.html`) and is published by `.github/workflows/pages.yml` when `main`
is updated.

- Expected URL: https://alv67.github.io/time-machine-scheduler/
- GitHub Pages on a private repository requires GitHub Pro/Team/Enterprise. On
  GitHub Free the repository must be public.

</details>

<details>
<summary><b>System paths touched</b></summary>

- `/Library/Application Support/TMScheduler/config.json`
- `/Library/Application Support/TMScheduler/last-run.json`
- `/Library/Application Support/TMScheduler/tmscheduler.log` (+ `.1`, `.2`, `.3`)
- `/Library/Application Support/TMScheduler/wake` (date of the armed wake)
- `/Library/LaunchDaemons/local.tmscheduler.plist`
- `/usr/local/bin/tmscheduler-daemon`
- `/usr/local/bin/tmscheduler-run`
- Time Machine `AutoBackup` / `AutoBackupInterval` preferences (only through
  "Open Time Machine Settings" and "Restore…")

</details>

<details>
<summary><b>Manual tests</b></summary>

- [ ] After **Save schedule**, `launchctl print system/local.tmscheduler` shows the
      daemon running, `active count = 1`, and the log records `daemon start`,
      `power: idle sleep prevented` and `wake: armed for …`.
- [ ] `sudo pmset -g sched | grep pmset` shows a wake two minutes before the
      scheduled time; after a reboot the daemon arms it again.
- [ ] With the session unlocked and the display off (`pmset displaysleepnow`), the
      scheduled run completes: `end: success` and a newer entry in `SnapshotDates`.
- [ ] With the session locked (Ctrl+Cmd+Q), the same run ends
      `failed device locked (RESULT 80)` — the limitation is macOS, not the app.
- [ ] Set the scheduled time a couple of minutes ahead with the app open: the log
      records `run: due, starting backup`, then `start` and `end: success`.
- [ ] With the Time Machine destination off or unreachable, the daemon writes
      `skip: destination … unreachable` and does not start Time Machine.
- [ ] With a backup already running, the daemon writes `skip: backup already running`.
- [ ] Changing time/days in the app only rewrites `config.json`: the daemon picks
      it up within 10 seconds without a restart.
- [ ] With the toggle OFF, the plist is removed and the daemon stops.
- [ ] **Restore…** removes plist, binaries and logs (including the 0.1.0 job) and
      restores `AutoBackup`/`AutoBackupInterval` to the selected values.
- [ ] `sudo kill -9` of the daemon: `launchd` restarts it and it re-arms the wake.
- [ ] After use, `tmutil listbackups` and manual backups from the system UI work.

</details>

<details>
<summary><b>Scheduled backups: awake, unlocked, and how the result is decided</b></summary>

Time Machine cannot read file-protection class A data (some caches and preferences
of every account) while the device is locked: the keys are evicted on lock and even
root cannot recover them. A backup that **starts** unlocked completes even if the
screen locks during the copy, because Time Machine takes its own assertion and logs
`Device locking is prevented`. So the requirement is: the device must be unlocked
when the backup starts.

macOS has no supported way for another process to unlock it:

- `MKBDeviceLockAssertion` (private, `MobileKeyBag`) is accepted by the keybag but
  has no effect without the entitlement `backupd` has: verified on macOS 27.2, the
  run still ends with `BACKUP_FAILED_DEVICE_LOCKED` (RESULT 80);
- an SSH session authenticates the user but does not unlock the device — tested,
  same failure;
- auto-login works only at boot and leaves the password on disk.

What works is keeping the display off and the **session unlocked**: System Settings
→ Lock Screen → "Require password after screen saver begins or display is turned
off" → a delay longer than the night (or Never; it is a per-user setting). Then the
daemon does one job:

1. while the option is on it holds an `IOPMAssertion`, so the Mac does not sleep;
2. two minutes before the scheduled time it arms a wake with
   `pmset schedule wake`, re-armed after every run and at every start (a scheduled
   wake does not survive a reboot);
3. every 10 seconds it compares the clock with `config.json` and, inside a 60 s
   window, runs `tmscheduler-run`;
4. if it notices it slept over the scheduled time, it logs
   `missed: Mac asleep at HH:MM` and notifies.

`tmutil startbackup --block` exits 0 even when the backup fails, so the result is
decided by the **newest** entry in `SnapshotDates` for the active destination in
`/Library/Preferences/com.apple.TimeMachine.plist`. Comparing the date, not the
number of entries: Time Machine thins old backups, so the count can go down while a
new one appears. When no newer date appears the run is recorded as `failed`, with
the Time Machine `RESULT` when it can be read (`80` = `BACKUP_FAILED_DEVICE_LOCKED`,
which means the session was locked).

Verification of a night: the log says `end: success` and the newest
`SnapshotDates` entry is from that night. A locked session gives
`end: failed device locked (RESULT 80)`; a problem with the destination gives a
different or unreadable `RESULT` and shows up as `failed` anyway.

Reproduction of the locked-session failure: lock the screen (Ctrl+Cmd+Q) and run

```bash
sudo /usr/local/bin/tmscheduler-run

sudo plutil -extract Destinations.0.SnapshotDates xml1 -o - \
    /Library/Preferences/com.apple.TimeMachine.plist
tail -3 "/Library/Application Support/TMScheduler/tmscheduler.log"
```

With the session locked no new date appears and the log says
`end: failed device locked (RESULT 80)`. The same script with the session unlocked
completes and adds a date — that is the whole difference the app can make.

Upgrade from 0.1.0 removes the old job (`local.tmscheduler.nightly`) before
installing the new one; `config.json` and the log are preserved. Rollback:
`sudo launchctl bootout system/local.tmscheduler`, remove
`/Library/LaunchDaemons/local.tmscheduler.plist` and the two binaries in
`/usr/local/bin`, then reinstall the 0.1.0 app and press **Save schedule**.

</details>

## Support

If the app is useful to you, you can [buy me a coffee](https://buymeacoffee.com/alv67).
The project stays free and open source for everyone.

## License

MIT — see [LICENSE](LICENSE). © 2026 Alessandro Varesi.
