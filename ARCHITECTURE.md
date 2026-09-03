# Architecture

```text
NetEase elog detector ----+
                          +--> direct config selection --> Playing / Idle / Unknown --> AutoHotkey
Windows GSMTC detector ---+                                                        ^
                                                             |
                                                     config/router.ini
        |
        +-- Playing or detector unavailable -> media keys pass through
        +-- Idle -> consume keys and run the Next / Prev actions
```

`src/index.ts` reads `player.provider` and directly selects the NetEase or GSMTC detector. There is no provider interface, factory, WebUI, or HTTP configuration layer.

`src/detector/netease-play-state.ts` retains only the upstream elog path, decoder, initial-state replay, file watching, and playback-state parsing. It intentionally has no song metadata, progress calculation, or SQLite access.

`automation/tws-media-router.ahk` owns the routing state machines and executes the four supported actions: `voice`, `enter`, `reset`, and `clear`. It uses AHK v2's native `IniRead`; no JSON parser or additional runtime is needed.

`config/router.ini` contains the detector command, polling interval, voice shortcut, clear-input keys, and Next/Prev sequences. The project root is derived from the automation script's own directory.

The GSMTC provider uses a small PowerShell 5.1 helper to call the official Windows Runtime API without a native Node dependency. It calls `GetCurrentSession()`, so multiple sessions follow the session Windows considers current rather than treating any historical Playing session as global playback. `Playing` maps to Playing; `Paused`, `Stopped`, and `Closed` map to Idle; no session, `Opened`, `Changing`, errors, and unrecognized values map to Unknown.

Audio-level detection is only a commented future contract in `config/router.ini`; it is not executed.
