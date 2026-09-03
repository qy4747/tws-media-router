# Architecture

```text
NetEase elog detector ----+
                          +--> config selection --> Playing / Idle / Unknown --> AutoHotkey
Windows GSMTC detector ---+                                                   ^
                                                                                |
                                                                        config/router.ini
        |
        +-- Playing, Unknown, dead or stale detector -> media keys pass through
        +-- fresh Idle -> consume keys and run the Next / Prev actions
```

`src/index.ts` reads `player.provider` and selects the NetEase or GSMTC detector. State changes are written as `Playing`, `Idle`, or `Unknown`; heartbeat events are written as `.` so AutoHotkey can verify that the detector remains fresh without treating repeated state as a state transition.

`src/detector/netease-play-state.ts` reads at most the latest 1 MiB of `cloudmusic.elog` during startup. If that tail does not contain reliable playback evidence, startup state is `Unknown`. Live updates are read serially from the exact previous offset to the observed file size. Decoded bytes from incomplete lines are retained across reads, so stream chunk boundaries and split UTF-8 characters cannot discard a playback-state record. Truncation or read failure moves the detector to `Unknown`.

`automation/router-state.ahk` contains the Next/Prev state machine and detector freshness gate. `automation/tws-media-router.ahk` owns the hotkeys and executes `voice`, `enter`, and `clear` actions. The clear action is permitted only when the second Prev occurs in the same active window recorded by the first Prev. The routing sequence has no time-window behavior.

`config/router.ini` contains the detector command, polling and stale timeout values, voice shortcut, and clear-input keys. The Next/Prev action sequence is implemented in AHK rather than stored in the INI file. The project root is derived from the automation script's own directory.

The GSMTC provider uses a small PowerShell 5.1 helper to call the official Windows Runtime API. It calls `GetCurrentSession()`, so multiple sessions follow the session Windows considers current. `Playing` maps to Playing; `Paused`, `Stopped`, and `Closed` map to Idle; no session, `Opened`, `Changing`, errors, and unrecognized values map to Unknown. The helper emits a status at least once per second, allowing the router freshness timeout to fail open if updates stop.

Audio-level detection is only a commented future contract in `config/router.ini`; it is not executed.
