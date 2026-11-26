<p align="center"><img src="website/public/assets/icon.png" width="128" alt="Dozex icon"></p>
<h1 align="center">Dozex</h1>
<p align="center">Keeps your Mac awake while your work runs (exports, renders, downloads, builds, AI agents), then lets it sleep the moment it's done.</p>
<p align="center">
  <a href="https://github.com/sekophungula/Dozex/releases/latest/download/Dozex.dmg"><b>Download for macOS</b></a> ·
  <a href="https://dozer.shakatec.co.za">Website</a>
</p>

---

Dozex is a small menu bar app for macOS. While Final Cut Pro exports, Blender renders, a big file downloads or uploads, Claude Code works or any terminal command runs, it stops your Mac from idle-sleeping. When the work finishes it releases the hold, so your normal Energy settings apply again. No changing sleep settings and no leaving a movie playing to keep the Mac up.

## Features

- **Menu bar toggle.** An eye icon at the top of the screen shows the status and turns Dozex on or off.
- **Control Center control** (macOS 26+). Add *Dozex* in Control Center → Edit Controls.
- **App watching.** Final Cut Pro, Compressor, iMovie, Premiere Pro, Media Encoder, After Effects, DaVinci Resolve, HandBrake, Logic Pro, GarageBand, Ableton Live, Pro Tools, Photoshop, Lightroom, Blender, Cinema 4D, Unity, Unreal, Xcode and Android Studio keep the Mac awake while they're exporting, rendering or building. Add any other app on the setup page. Each app can be set to *When busy*, *While open* or *Off*.
- **Download and upload watching.** A big download in any browser, an upload to YouTube, Dropbox or WeTransfer, a cloud folder syncing or an online backup keeps the Mac awake until it finishes. Light traffic like music or messages doesn't count. Turn it off with *Watch downloads*.
- **Accurate Claude tracking** through Claude Code hooks, with a fallback that watches for busy `claude` processes.
- **Terminal watching.** A command running in any terminal (Terminal, iTerm, Ghostty, Warp, VS Code, tmux) keeps the Mac awake. CLI agents such as Codex, Gemini CLI and Aider, plus editors, `ssh` and REPLs, count only while they're using CPU, so an idle session doesn't keep the Mac up. A short CPU spike doesn't count: they need to keep working for about 10–15 seconds. Turn it off with *Watch Terminal*.
- **Grace period.** Stays awake for a configurable time after Claude finishes, so back-to-back prompts don't let the Mac drop off between them.
- **Keep awake indefinitely**, for when you want plain caffeinate-style behaviour.
- **Optional display-awake mode** and a **"done" notification**.
- **Open at login.**

## Install

1. Download `Dozex.dmg` from the [latest release](https://github.com/sekophungula/Dozex/releases/latest) and drag Dozex into Applications.
2. Dozex is ad-hoc signed and not notarized, so macOS blocks it the first time. Open **System Settings → Privacy & Security** and click **Open Anyway**, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Dozex.app
   ```
3. On the setup page, click **Connect Claude Code**.

## How it works

| Piece | What it does |
| --- | --- |
| `PowerAssertion` | Holds an IOKit `PreventUserIdleSystemSleep` assertion (the same mechanism `caffeinate` uses) and, if you choose, `PreventUserIdleDisplaySleep`. |
| `TerminalMonitor` | Every few seconds, reads `ps` and checks each terminal's foreground job. A non-shell command counts as work. Known agents and interactive programs count only while they stay above 3% CPU (summed over that terminal). |
| `AppMonitor` | Matches running apps against the watch list by bundle ID. An app set to *When busy* counts once it and the processes it started use 10% CPU or more for most of the last 15 seconds. *While open* counts as long as the app runs. |
| `NetworkMonitor` | Reads the byte counters of the Mac's Wi-Fi and Ethernet connections (no permissions needed). Traffic of 250 KB/s or more in either direction, kept up for about 15 seconds, counts as a transfer. |
| `BusyTracker` | Smooths readings for apps, agents, `claude` processes and network traffic: busy after 4 of the last 5 readings are hot, idle again once at most 1 is. |
| `HookInstaller` | Adds hooks for `UserPromptSubmit`, `PreToolUse` and `PostToolUse` (mark busy) and for `Stop` and `SessionEnd` (mark done) to `~/.claude/settings.json`. Each hook calls a tiny shell script that creates or deletes a marker file per session in `~/Library/Application Support/Sleepable/sessions`. |
| `ClaudeMonitor` | Every 3 seconds it counts live session markers and `claude` processes that keep using CPU. Stale markers left behind by crashed sessions are cleaned up automatically. |
| `DozexControl.appex` | A WidgetKit `ControlWidgetToggle` for Control Center. It talks to the app through a small state file and Darwin notifications. |

Disconnecting from the setup page removes the hooks again. A copy of your original settings is saved as `~/.claude/settings.json.sleepable-backup`.

**Limitation:** a MacBook with its lid closed and no external display will always sleep. Keep the lid open for long runs.

## Build from source

You need Xcode 26 or later (for the Control Center extension SDK). No Xcode project is required:

```bash
Scripts/build.sh            # → build/Dozex.app
Scripts/build.sh --package  # → also build/Dozex.zip and build/Dozex.dmg
```

Set `VERSION=1.2.0` to stamp a version, or `SIGN_IDENTITY="Developer ID Application: …"` to sign with your own certificate.

## License

MIT. Not affiliated with Anthropic.
