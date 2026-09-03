# Agent adaptation notes

Keep this project simple and configuration-driven.

- Personalize `config/router.ini`; do not add a WebUI or configuration service.
- Preserve `#UseHook`, Unknown fail-open, and the verified AHK Next/Prev state-machine semantics unless the task explicitly changes them.
- Keep `player.provider=netease` as the verified default. `gsmtc` is the existing alternative.
- After configuration changes, run `npm test`, then restart `automation/tws-media-router.ahk`.
- Add a new detector directly in `src/index.ts`; do not recreate a provider factory or interface layer.
- The commented `[audio_level]` block is a future implementation hint only. If implemented, debounce low level before Idle and return Unknown on device/API failure.
