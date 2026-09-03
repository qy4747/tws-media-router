# tws-media-router

This project is agent-managed. Adapt environment-specific behavior through `config\router.ini`, then restart the AHK script; rebuild only when source code changes.

## Requirements

- Windows
- Node.js 20.6 or newer
- AutoHotkey v2
- For `player.provider=netease`: NetEase CloudMusic desktop client with `cloudmusic.elog`
- For `player.provider=gsmtc`: Windows 10 version 1809 or newer

## Build and run

```powershell
npm install
npm run build
```

Run `automation\tws-media-router.ahk`. The project path is derived from the script location, and the script never activates a window.

The selected provider writes state changes as `Playing`, `Idle`, or `Unknown`, plus lightweight heartbeat markers. Until a known state arrives, on `Unknown`, if the provider process exits, or if detector updates become stale, media keys pass through unchanged.

## Configuration

`config\router.ini` controls the player-state provider, polling and freshness intervals, voice/transcription shortcut, and clear-input keystrokes. The Next/Prev action sequence itself is implemented by the AHK routing state machine.

```ini
[player]
provider=netease
gsmtc_poll_interval_ms=500

[detector]
poll_interval_ms=100
stale_after_ms=3000
```

Supported providers are `netease` and `gsmtc`. `netease` remains the default. GSMTC observes the current session selected by Windows; no session or an indeterminate/error state becomes `Unknown` and leaves media keys untouched.

The fixed routing actions are:

- `voice`: send the configured transcription shortcut
- `enter`: press Enter
- `reset`: reset the Next sequence without changing text
- `clear`: send the configured select-all and delete keystrokes

The second Prev clear is allowed only when the active window is still the same window recorded by the first Prev. If focus moved to another window, clear is cancelled and the Prev sequence resets.

The project directory is derived from the AHK script location, so moving the whole project does not require editing an absolute path.

## Tests

`npm test` builds the TypeScript code and runs the Node tests. The Windows GitHub Actions workflow also runs `test\router-state.test.ahk` with AutoHotkey v2 so the routing state machine, fail-open freshness gate, and same-window clear guard are tested from the actual AHK implementation.

## Future audio-level detector

`config\router.ini` contains a disabled commented template. A future agent may implement it using the system audio peak meter. It must debounce silence before returning Idle and must return Unknown—not Idle—when the device or API cannot be read.
