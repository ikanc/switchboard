# Switchboard

A tiny macOS menu-bar app that launches and manages the long-running processes you run all day — dev servers, tunnels, build watchers, AI relays, anything — from one place.

It lives as a ⚡ bolt icon in the menu bar. Click it to see a list of services with live status, tail the last lines of logs, and start / stop / restart without hunting for a terminal tab.

## What it does

- **Runs long-running services** (dev servers). Each has a name, command, working directory, optional port, icon, and color.
- **Auto-restart on crash** — up to 3 retries with a 5s delay. Gives up after that so a broken config doesn't loop forever.
- **Port conflict recovery** — if a service crashes with `EADDRINUSE`, the app finds the blocking PID via `lsof`, kills it, and relaunches.
- **Stale process cleanup** — ngrok-style "already online" errors trigger a `pgrep -f` kill of the old instance (excluding its own PID) before retrying.
- **Shell env shim** — spawned processes are launched under `/bin/zsh -c` with Homebrew `shellenv` and NVM sourced, because GUI-launched apps on macOS don't inherit an interactive shell's `PATH` / Node version.
- **Log tailing** — stdout and stderr are merged into a per-service ring buffer. Expand a row to see it live; copy or clear from the expanded view.
- **One-time commands** — same config shape as a service, but runs once and exits. No auto-restart, no port watching. Useful for scripts, migrations, seeds, or anything you'd otherwise `cd` + run once.
- **Keep awake (lid closed)** — a footer toggle that prevents the Mac from sleeping when you close the lid, so your services keep running. See below.
- **Launch at Login** and an **About** panel in the ⚙︎ settings menu.

## Keep awake

The ☕️ toggle in the footer keeps the Mac awake **even with the lid closed** (no external display needed). It turns orange while active so you don't forget it's on.

Under the hood this flips `pmset disablesleep`, which is the only switch that survives a lid close — `caffeinate`/`IOPMAssertion` only block *idle* sleep while the lid is open. That requires root, so:

- The **first** time you enable it, you'll get one admin-password prompt. It installs a tightly-scoped rule at `/etc/sudoers.d/switchboard-pmset` that permits **only** `pmset -a disablesleep 0|1` for your user — nothing else.
- **Every toggle after that is silent** — no password, no prompt.
- The flag is cleared by a reboot. The toggle always reflects the live `pmset -g` state, so after a reboot it simply shows off again.

To remove the password-free grant later: `sudo rm /etc/sudoers.d/switchboard-pmset`.

## Architecture

Single-target SwiftUI app using `MenuBarExtra` (macOS 13+).

| File | Role |
| --- | --- |
| `Switchboard/ServiceConfig.swift` | Codable config model (name, command, dir, port, icon, color, `isOneShot`). Ships with default services + available icons/colors. |
| `Switchboard/ConfigManager.swift` | Loads/saves configs as JSON in `~/Library/Application Support/Switchboard/services.json`. Seeds defaults on first launch. |
| `Switchboard/ServiceProcess.swift` | Wraps a `Foundation.Process`. Owns status, logs, uptime, auto-restart logic, port/stale conflict recovery, and process-tree kill. |
| `Switchboard/ServiceManager.swift` | `@ObservableObject` that owns the config list + `ServiceProcess` instances. Handles CRUD and bulk actions (start all / stop all / restart all). |
| `Switchboard/SleepPreventer.swift` | The keep-awake toggle: reads live `pmset` state, installs the scoped sudoers rule on first use, and applies changes silently thereafter. |

Views live under `Switchboard/Views/`:

| View | Role |
| --- | --- |
| `ServiceListView` | Main menu-bar panel. Header counter, scrollable service rows, footer with Start All / Stop All / Add / keep-awake / settings / Quit. |
| `ServiceRowView` | One row. Status dot + name + status line, inline start/stop/restart buttons, expandable log panel, context menu (right-click) for edit/delete. |
| `ServiceFormView` | Add / edit form. Icon picker, color picker, folder picker, one-time-command toggle, live preview. |

Config is stored at `~/Library/Application Support/Switchboard/services.json` — deleting this file resets the app to the built-in defaults next launch.

## Setup

```bash
./setup.sh          # installs xcodegen if missing, runs `xcodegen generate`, opens Xcode
```

Then in Xcode: ⌘R. The bolt icon appears in your menu bar.

CLI-only build:

```bash
xcodebuild -project Switchboard.xcodeproj -scheme Switchboard -configuration Release build
```

Build + install to `/Applications` (with optional version bump):

```bash
./publish.sh            # build current version and install
./publish.sh patch      # bump x.y.Z, then build + install
```

The project uses ad-hoc signing (`CODE_SIGNING_ALLOWED: NO`). It runs fine locally; for distribution to other machines without Gatekeeper friction you'd need Developer ID signing + notarization.

## Services vs. Commands

The menu-bar panel has two tabs:

- **Services** — long-running processes (dev servers, tunnels). Auto-restart on crash, optional port watching, "Start All" / "Stop All" bulk controls.
- **Commands** — one-time scripts. Run once and exit. No auto-restart, no port watching. Hitting `+` from the Commands tab pre-selects the one-shot toggle in the form.

Flipping the "One-time command" toggle while editing moves the item between tabs. Saving from the form takes you back to the matching tab.

### How one-time commands behave

- No auto-restart. Non-zero exit → `Crashed`; zero exit → `Finished`.
- No port conflict retry. The port field is hidden because it isn't relevant.
- The row shows a `one-time` badge, and the `Finished` state shows a play button to re-run.
- Excluded from "Start All" and from the header's `running/total` counter.

Examples of things that fit well as one-time commands: `git pull` across a repo, `composer install`, `npm install`, DB migrations, seeds, cache clears, codegen.

## Adding / editing a service

Click **+** in the footer (or right-click a row → Edit).

- **Name** — shown in the row.
- **Command** — run under `/bin/zsh -c` after `cd`-ing to the working directory. Homebrew + NVM are already sourced for you.
- **Working directory** — `~` gets expanded. Use the 📁 button to pick a folder; paths under `$HOME` are normalized back to `~/...`.
- **One-time command** — toggles one-shot mode (described above).
- **Port** (services only, optional) — if set, `EADDRINUSE` errors trigger `lsof -ti tcp:<port> | xargs kill -9` followed by a retry.
- **Icon / color** — purely cosmetic.

## License

MIT — see [LICENSE](LICENSE).
