# LG Dual-Mode Switcher

Automatically switches an LG UltraGear Dual-Mode monitor to **1080p 330 Hz** while a game runs, and back to **4K 165 Hz** when it closes. A small hub window lets you manage which games trigger the switch.

Built and tested on the **LG 32GX850A** under Windows 11.

## How it works

- **Switching:** LG doesn't expose Dual-Mode over DDC/CI, so the script presses the Dual-Mode keyboard shortcut of the **LG Switch** app.
- **Detecting the mode:** the monitor reports a different hardware ID in each mode (`GSM7856` = 4K, `GSM7859` = Dual-Mode). The script reads that ID, so it only presses the shortcut when the mode actually needs to change. It retries if the press gets lost while a game is starting.
- **Detecting games:** the watcher checks the process list every 3 seconds against `games.json`. It doesn't read game memory or open handles to game processes.

## Requirements

- Windows 10/11 with PowerShell 5.1 (preinstalled)
- **LG Switch** (LG's monitor app, from your monitor's support page on lg.com) running in the background, with a keyboard shortcut assigned to Dual-Mode (default in this repo: **Alt+Shift+D**)

## Setup

1. In LG Switch, assign a shortcut to Dual-Mode and enable "start with Windows". Use Ctrl and/or Alt (optionally with Shift) plus a letter, digit or F-key.
2. Double-click **`Hub.cmd`**. Under **LG Switch Dual-Mode shortcut**, click the box and press the same shortcut. It's saved to `settings.json`.
3. Click **Start** under Watcher and tick **Start watcher with Windows**.

## Usage

**Hub (`Hub.cmd`)**
- Shows the current mode, with buttons to switch manually
- **Add running app...**: start the game, then pick its window from the list
- **Add .exe...**: pick the game's executable
- **Remove**: removes the selected game
- Start/stop the watcher, toggle autostart and open the log
- Set the LG Switch shortcut (takes effect immediately, even for a running watcher)

Changes to the game list apply immediately, so you don't need to restart the watcher.

**Double-click shortcuts:** `Dual-Mode ON (1080p 330Hz).cmd` and `Dual-Mode OFF (4K 165Hz).cmd`

**Command line**
```powershell
.\monitor_mode.ps1 -Mode On | Off | Toggle
.\monitor_mode.ps1 -Watch              # switch automatically for games in games.json
.\monitor_mode.ps1 -InstallAutostart   # run the watcher hidden at every login
```

## Game list

`games.json` holds one entry per game. Process names are written without `.exe`:

```json
[
  { "name": "VALORANT", "processes": ["VALORANT-Win64-Shipping", "VALORANT"] }
]
```

If a game starts through a launcher, list the launcher's process too. The switch then happens before the game goes fullscreen, which is more reliable.

## Other LG Dual-Mode monitors

The hardware IDs are specific to the 32GX850A. To find yours, run this once in each mode:

```powershell
Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID | Select-Object InstanceName
```

Then set `$MonitorPrefix` (the part both IDs share) and `$DualModeId` (the Dual-Mode ID) in `monitor_mode.ps1`.

## Troubleshooting

- **It doesn't switch:** check that LG Switch is running and that its shortcut matches the one in the hub. Then look at `monitor_mode.log` (Hub → Open log), which records what was detected, what was sent and which window was in the foreground.
- **Your keyboard layout changes:** Alt+Shift is also Windows' shortcut for switching input languages. Use a Ctrl+Alt shortcut instead.

## Anti-cheat

The tool doesn't touch game processes. It only lists running processes and sends one key press to LG Switch when a game starts or closes. Use it at your own risk; no anti-cheat vendor has approved it.
