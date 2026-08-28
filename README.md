# Uptime Monitor

Monitor a single URL from the Omarchy bar. Green dot when the site is up, red when it's down. Click to configure.

## Install

```sh
omarchy plugin add https://github.com/SjoenH/omarchy-uptime-monitor.git --enable
```

## Usage

- A colored dot appears in the bar — **green** = online, **red** = offline
- Hover for a quick status tooltip (URL + state + check cadence)
- Click to open the panel:
  - **URL** — the address to probe. The scheme is optional; `https://` is added if omitted.
  - **Label** (optional) — shown next to the dot in the bar
  - **Check every** — either a simple interval (number + unit) or a cron expression
- The first check runs immediately on load; each save resets the schedule timer

The URL, label, and schedule persist across restarts via `shell.json`.

## Default

Ships unmonitored. Enter a URL in the panel to start; it checks every 30 seconds by default.

## Remove

```sh
omarchy plugin remove no.koka.uptime-monitor
```
