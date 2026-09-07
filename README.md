# headphone-disconnect

Drops your Bluetooth headphones from this Mac when it goes to sleep, and reconnects them when
it wakes up.

## Why

Multipoint headphones (JBL, Sony, Bose — anything that isn't AirPods) hold one link per device
and keep routing audio to whichever source last claimed it. A sleeping Mac keeps its Bluetooth
link alive on purpose, so it can be woken by a Bluetooth keyboard or mouse. The headphones
therefore still think the Mac owns them, and audio from your phone goes nowhere until you
manually disconnect from the Mac.

This is how macOS is designed, not a bug in a particular release — macOS only does automatic
source switching for Apple's own headphones (AirPods/Beats), and it exposes no multipoint API
to anyone else. So this utility does the manual step for you, on the sleep/wake events.

## Install

### Homebrew

```sh
brew tap mon4our/tap
brew install headphone-disconnect
brew services start headphone-disconnect
```

The formula compiles from source on your machine, so there is no Gatekeeper prompt and nothing
to un-quarantine. To get a clickable app in Finder as well:

```sh
ln -s "$(brew --prefix)/opt/headphone-disconnect/Headphone Disconnect.app" ~/Applications/
```

### From source

```sh
git clone https://github.com/mon4our/headphone-disconnect.git
cd headphone-disconnect
./install.sh                       # manages whatever audio device is connected right now
./install.sh 88:92:CC:1B:6D:03     # or name the device(s) explicitly
```

That builds `~/Applications/Headphone Disconnect.app`, installs a CLI at
`~/.local/bin/headphone-disconnect`, writes `~/.config/headphone-disconnect/config.json`, and
loads a LaunchAgent so it starts at login.

`./uninstall.sh` removes the agent, app, and CLI, keeping your config and log.

### Bluetooth permission

**macOS asks for Bluetooth permission the first time.** Allow it, or the app is killed by TCC the
moment it touches Bluetooth. Because the app is only ad-hoc signed, the signature changes on every
rebuild and macOS may ask again after an update.

## Opening it

The app lives in `~/Applications` with a real icon, so it is double-clickable in Finder and
findable in Spotlight — useful after you Quit it from the menu. It is a menu bar app
(`LSUIElement`), so opening it puts the headphones icon back in the menu bar; there is no Dock
icon and no window. Day to day you never need to open it: the LaunchAgent starts it at login.

## The menu bar

A headphones icon appears in the menu bar; it dims when nothing it manages is connected.

```
  JBL Tune 770NC — Connected
  ---
  Disconnect from This Mac
  ---
  [x] Disconnect When Mac Sleeps
  [x] Reconnect When Mac Wakes
  ---
  Headphones >
      [ ] Kunika's Headset
      [x] JBL Tune 770NC (connected)
  ---
  Open Log...
  Quit
```

- **Disconnect from This Mac** — the manual version of the whole utility, for when you want your
  phone to take the headphones right now without sleeping the Mac.
- **Disconnect When Mac Sleeps** — pause the automatic behaviour without uninstalling anything.
- **Headphones** — which paired audio devices to manage. Ticking one adds it to the config.
- **Quit** stays quit; the LaunchAgent only restarts the app if it crashes. Bring it back with
  `launchctl kickstart gui/$UID/com.github.mon4our.headphone-disconnect` or by opening the app.

The menu and the config file are the same state, so a toggle in the menu is visible to the CLI
and vice versa.

## Use

```sh
headphone-disconnect status       # configured + paired audio devices, and their state
headphone-disconnect disconnect  # do it now
headphone-disconnect connect     # undo it now
headphone-disconnect dump-menu   # print what the menu shows, without clicking it
headphone-disconnect menubar     # the UI + watcher (what the LaunchAgent runs)
headphone-disconnect watch       # watcher only, no UI
```

Log: `~/Library/Logs/headphone-disconnect.log`

```sh
tail -f ~/Library/Logs/headphone-disconnect.log
```

## Config

`~/.config/headphone-disconnect/config.json`

| key | default | meaning |
| --- | --- | --- |
| `devices` | — | Bluetooth addresses to manage. Set from the menu's Headphones submenu, or `headphone-disconnect status` to list addresses. |
| `enabled` | `true` | The menu's "Disconnect When Mac Sleeps" toggle. |
| `reconnectOnWake` | `true` | Reconnect on wake. Set `false` to only ever disconnect. |
| `reconnectDelay` | `3` | Seconds to wait after wake before the first attempt; the Bluetooth stack needs a moment. |
| `reconnectAttempts` | `6` | How many times to try before giving up (headphones may be off, or on your phone). |
| `reconnectInterval` | `4` | Seconds between attempts. |
| `skipDarkWake` | `true` | Don't reconnect during dark wake (Power Nap, backups). Waits for the display to come on. |
| `darkWakeGraceSeconds` | `120` | How long to wait for the display before deciding this was a dark wake and staying disconnected. |

Restart the agent after editing:

```sh
launchctl kickstart -k gui/$UID/com.github.mon4our.headphone-disconnect
```

## How it works

`IORegisterForSystemPower` gives the process the real power-management events, and — unlike the
`NSWorkspace` notifications — it lets us hold off sleep until our work is done:

- `kIOMessageSystemWillSleep` → disconnect each device, verify it stayed down (headphones
  re-establish the link fast, so this retries), *then* acknowledge the sleep. The link is gone
  before the Mac is actually asleep.
- `kIOMessageSystemHasPoweredOn` → reconnect, but only the devices we disconnected ourselves,
  and only once the display is on, so a Power Nap wake doesn't steal your headphones back while
  you're using them on your phone.

The watcher and the UI are one process, so the menu always reflects what the watcher will do.
Every power event re-reads the config file first, so editing it by hand takes effect without a
restart.

Two non-obvious details worth knowing if you touch the code. First, `IOBluetoothDevice.closeConnection()`
returns success immediately but the link only really drops once the run loop is serviced. A
short-lived process that exits right after calling it leaves the headphones connected. Both the
connect and disconnect paths pump the run loop until the state actually changes.

Second, a *bundled* app that touches Bluetooth is killed by TCC (`OS_REASON_TCC`) unless
`Info.plist` carries `NSBluetoothAlwaysUsageDescription`. The CLI doesn't hit this, because a
plain binary inherits the permissions of whatever launched it.

## Notes

- Verified on macOS Sonoma 14.2 (Apple silicon) with JBL Tune 770NC. `Info.plist` claims 13.0 as
  the minimum; Ventura and Sequoia are untested, though nothing here uses a recent API.
- Layout: `main.swift` (CLI entry) and `Sources/` (the pieces), `Resources/Info.plist` and
  `Resources/AppIcon.icns` for the bundle, `build.sh` for the compile — shared by `install.sh`
  and the Homebrew formula so the flags can't drift. No Xcode project.
- The icon is generated, not hand-drawn: `./Resources/make-icon.sh` re-renders it from the
  `headphones` SF Symbol.
- If the headphones are actively connected to your phone when the Mac wakes, the reconnect may
  fail (their second slot is busy) — you'll see "giving up" in the log. That's harmless.
- A wake where you immediately want headphones on the Mac takes ~3-5 seconds to reconnect.
- Bluetooth stays on, so a Bluetooth keyboard or mouse can still wake the Mac. Tools like
  Bluesnooze turn the whole radio off instead, which also disables wake-on-Bluetooth.
