# tws-media-router

This project is intentionally agent-managed: there is no WebUI or configuration service. Adapt behavior by editing `config\router.ini`, then restart the AHK script; rebuild only when source code changes.

## Requirements

- Windows
- Node.js 20.6 or newer
- AutoHotkey v2
- NetEase CloudMusic desktop client using `cloudmusic.elog`

## Build and run

```powershell
npm install
npm run build
```

Run `automation\tws-media-router.ahk`. The project path is derived from the script location, and the script never activates a window.

The selected provider writes `Playing`, `Idle`, or `Unknown` to stdout. Until a known state arrives, on `Unknown`, or if the provider process exits, media keys pass through unchanged.

## Configuration

`config\router.ini` controls the player-state detector, polling intervals, voice/transcription shortcut, clear-input keystrokes, and action sequences. Configuration changes take effect after rebuilding when source changed and restarting the AHK script.

```ini
[player]
provider=netease
gsmtc_poll_interval_ms=500
```

Supported providers are `netease` and `gsmtc`. `netease` remains the default. GSMTC requires Windows 10 version 1809 or newer and observes the current session selected by Windows; no session or an indeterminate/error state becomes `Unknown` and leaves media keys untouched.

Supported action names are:

- `voice`: send the configured transcription shortcut
- `enter`: press Enter
- `reset`: reset the Next sequence without changing text
- `clear`: send the configured select-all and delete keystrokes

The project directory is derived from the AHK script location, so moving the whole project does not require editing an absolute path.

## Future audio-level detector

`config\router.ini` contains a disabled commented template. A future agent may implement it using the system audio peak meter. It must debounce silence before returning Idle and must return Unknown—not Idle—when the device or API cannot be read.

Not included: WebUI, HTTP service, Audio Session implementation, automatic focus, installer, packaging, or publishing.
