# Switchboard Roadmap

Where Switchboard is headed — from a personal launcher to a structured local dev
environment manager. Contributions welcome on anything here.

## ✅ Done

- **Main window** — a full window alongside the menu-bar dropdown (NordVPN-style:
  dropdown for quick actions, window for in-depth control). Closing it leaves
  every service running.
- **Projects / groups** — organize services into groups; start/stop a whole
  group (stack) at once from the window sidebar.
- **Per-service environment variables** — exported before the command runs.
- **Quick actions** — open the served URL, reveal the working dir in Finder,
  open a Terminal there, copy the command.
- **Cleaner logs** — ANSI escape codes stripped in the window log view.

## 🎯 Next — orchestration

- **Health checks / readiness** — wait until a port is actually listening before
  marking a service "running" (and before starting dependents).
- **Dependency ordering** (`depends_on`) — boot services in the right order.
- **Per-service restart policy** — configurable max retries / backoff (currently
  hard-coded 3× / 5s).

## 🎯 Next — interop

- **Import** from `Procfile`, `docker-compose.yml`, and `package.json` scripts.
- **Per-repo `.switchboard.json`** — commit a project's service set so a team
  shares one setup.

## 🎯 Next — logs that scale

- Search / filter within logs, timestamps, full ANSI **color** rendering.
- Persist logs to disk with rotation; an aggregated all-services view.

## 🎯 Next — observability

- CPU / memory per process.
- Desktop notification when a service crashes.

## 🎯 Next — product / distribution

- **App icon** (currently the default — `AppIcon.appiconset` is empty).
- **Code signing + notarization** so others can open it without Gatekeeper
  friction.
- **Sparkle auto-update** + a GitHub Actions release workflow (build → notarize →
  attach DMG).
- Unit tests + CI.
