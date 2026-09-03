# Agent adaptation notes

Keep this project simple and configuration-driven.

- Personalize `config/router.ini` for environment-specific settings.
- Match `[transcription_shortcut]` directly to the recording shortcut configured in the user's transcription software.
- Preserve `#UseHook`, Unknown fail-open, and the verified AHK Next/Prev state-machine semantics unless the task explicitly changes them.
- Keep `player.provider=netease` as the verified default. `gsmtc` is the existing alternative.
- After configuration changes, run `npm test`, then restart `automation/tws-media-router.ahk`.
- For an installed user setup, create a current-user Windows startup entry that launches `automation/tws-media-router.ahk` after sign-in. Keep it user-level and do not require administrator privileges.
- Add a new detector directly in `src/index.ts` when needed.
- The commented `[audio_level]` block is a future implementation hint only. If implemented, debounce low level before Idle and return Unknown on device/API failure.
