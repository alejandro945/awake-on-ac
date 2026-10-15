# awake-on-ac

[![ci](https://github.com/alejandro945/awake-on-ac/actions/workflows/ci.yml/badge.svg)](https://github.com/alejandro945/awake-on-ac/actions/workflows/ci.yml)

Keep a MacBook awake with the lid closed **while it is on AC power**, and let it sleep normally **on battery**. Built for desks where several closed MacBooks share one monitor, keyboard and mouse through a KVM switch.

| Power | What awake-on-ac does |
|---|---|
| Charger connected | The Mac never sleeps, even with the lid closed and no display |
| Charger disconnected | Normal sleep. If the lid is already closed and there is no external display, it puts the Mac to sleep right away (the "into the bag" case) |
| Agent stopped or uninstalled | Normal sleep is restored |

## Why

With the lid closed, macOS only stays awake in **clamshell mode**: AC power plus an active external display. A KVM switch that sends the monitor to another computer ends clamshell mode, so the MacBook you just left goes to sleep within seconds:

```
Entering Sleep state due to 'Clamshell Sleep' ... Using AC (Charge:100%)
```

`sudo pmset -a disablesleep 1` prevents it, but it is a global switch: if you forget to turn it off, the laptop also stays awake in your bag. awake-on-ac ties that switch to the power source, automatically.

## How it works

- A small Swift agent subscribes to the macOS power-source notification (`IOPSNotificationCreateRunLoopSource`). It reacts the moment the charger is connected or disconnected and does nothing in between: no polling.
- It runs `sudo -n pmset -a disablesleep 1` on AC and `... 0` on battery. A sudoers rule allows exactly those two commands without a password, and nothing else.
- On battery, if the lid is closed and macOS reports that this would put it to sleep (`AppleClamshellCausesSleep`, meaning no external display), it runs `pmset sleepnow`.
- launchd starts it at login and restarts it if it exits. When launchd stops it (logout, uninstall), it sets `disablesleep 0` before exiting.

The whole agent is one file: [`src/awake-on-ac.swift`](src/awake-on-ac.swift).

## Requirements

- macOS 12 or later. Developed on macOS 27 with Apple silicon (M3 Pro). It uses only public IOKit APIs, so Intel Macs should work too, but they have not been tested.
- Command Line Tools for the Swift compiler: `xcode-select --install` (skip it if `swiftc --version` already works).
- An administrator account: the installer asks for your password once, to install the sudoers rule.

## Install on each Mac

Repeat these steps on every MacBook that should stay awake. The agent is built on each Mac, so there are no downloaded binaries to trust.

1. **Open Terminal on that Mac**, logged in as the user who works on it (not root).

2. **Clone the repository:**

   ```bash
   git clone https://github.com/alejandro945/awake-on-ac.git ~/awake-on-ac
   ```

3. **Run the installer.** It asks for your password once, for the sudoers rule:

   ```bash
   cd ~/awake-on-ac && ./scripts/install.sh
   ```

   It builds the agent into `~/.local/bin/awake-on-ac`, installs `/etc/sudoers.d/awake-on-ac` (validated with `visudo` first), installs the LaunchAgent and starts it. If macOS shows **"Background Items Added"**, leave it allowed.

4. **Check that it is running:**

   ```bash
   ./scripts/status.sh
   ```

   With the charger connected you should see `agent: running` and `SleepDisabled: 1`.

5. **Test it with the lid open.** Disconnect the charger for 5 seconds and connect it again. You should get two notifications, "Normal sleep" and "Always awake", and two new lines in the log. Keep the lid open for this test: unplugged with the lid closed and no display, the agent puts the Mac to sleep, which is the intended behavior.

6. **Test the real case.** With the charger connected and the lid closed, switch the KVM to another computer, wait five minutes and switch back. The Mac should still be awake. To confirm that it did not sleep:

   ```bash
   pmset -g log | grep "Clamshell Sleep" | tail -3
   ```

   No new lines since the test started means it stayed awake.

Notifications are shown through `osascript`, so macOS lists them under **Script Editor**. If they do not appear, allow them in System Settings → Notifications → Script Editor. The agent works the same without them.

## Update

```bash
cd ~/awake-on-ac && git pull && ./scripts/install.sh
```

## Uninstall

```bash
cd ~/awake-on-ac && ./scripts/uninstall.sh
```

It stops the agent, restores normal sleep, and removes the binary, the LaunchAgent and the sudoers rule. The log stays at `~/Library/Logs/awake-on-ac.log`.

## Files it installs

| Path | What |
|---|---|
| `~/.local/bin/awake-on-ac` | The agent |
| `~/Library/LaunchAgents/io.github.alejandro945.awake-on-ac.plist` | Starts it at login and keeps it running |
| `/etc/sudoers.d/awake-on-ac` | `pmset -a disablesleep 0` and `1` without a password, for your user only |
| `~/Library/Logs/awake-on-ac.log` | One line per power change |

## Security and side effects

- **The sudoers rule is narrow.** It allows two exact commands, `/usr/bin/pmset -a disablesleep 0` and `1`, for one user. Any other `sudo` command still asks for the password. The installer proves this by clearing the cached credentials (`sudo -k`) and running the command with `sudo -n`.
- **On AC power, the Mac cannot sleep at all**, not even with the lid closed or from the Apple menu. That is the point, but keep it in mind: a closed MacBook under load runs warmer. Give it some air, for example in a vertical stand.
- **Lock the screen.** These Macs stay awake for hours. Set System Settings → Lock Screen to require the password immediately.
- **Battery health.** A MacBook that is always plugged in benefits from a charge limit (for example, 80%).

## Troubleshooting

| Symptom | Check |
|---|---|
| `status.sh` says `not loaded` | `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/io.github.alejandro945.awake-on-ac.plist`, then look at the log |
| The log says `pmset exited with 1` | The sudoers rule is missing or for another user: run `./scripts/install.sh` again |
| It still sleeps when you switch the KVM | Run `status.sh` with the charger connected: `SleepDisabled` must be `1`. If it is `0`, the agent is not running or the charger is not detected |
| No notifications | Allow Script Editor in System Settings → Notifications |
| Another app also manages sleep (Amphetamine, caffeinate scripts) | Disable it: two tools changing `disablesleep` will fight |

## Alternatives

- **An EDID emulator** (a small HDMI or DisplayPort dongle) between each MacBook and the KVM, or a KVM with built-in EDID emulation. The Mac always sees a display, so clamshell mode never ends. This is the hardware fix and needs no software.
- **Amphetamine** with a "power adapter connected" trigger and closed-display mode. On Apple silicon it also needs its separate Power Protect add-on.
- **`sudo pmset -a disablesleep 1` by hand**, if you never move the laptops. Remember to turn it off before you take one away.

## License

[MIT](LICENSE)
