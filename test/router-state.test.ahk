#Requires AutoHotkey v2.0
#Include %A_ScriptDir%\..\automation\router-state.ahk

AssertEqual(actual, expected, message) {
    if actual != expected
        throw Error(message " (expected=" expected ", actual=" actual ")")
}

router := RouterState()
AssertEqual(router.Next(), "voice", "first Next starts transcription")
AssertEqual(router.Next(), "voice", "second Next stops transcription")
AssertEqual(router.Next(), "enter", "third Next sends Enter")
AssertEqual(router.Next(), "voice", "Next sequence loops without a time window")

router.Reset()
AssertEqual(router.Prev(1001), "reset", "first Prev resets Next sequence")
AssertEqual(router.Prev(1001), "clear", "second Prev clears in the same window")

router.Reset()
AssertEqual(router.Prev(1001), "reset", "first Prev records active window")
AssertEqual(router.Prev(2002), "cancel", "window change cancels destructive clear")
AssertEqual(router.Prev(2002), "reset", "cancelled clear starts a new Prev sequence")

router.Reset()
router.Next()
router.Next()
router.Reset()
AssertEqual(router.Next(), "voice", "state reset restarts Next sequence")
AssertEqual(router.Prev(3003), "reset", "state reset restarts Prev sequence")

gate := DetectorGate(3000)
AssertEqual(gate.GetRouteDecision(true, 1000), "pass", "unknown detector state fails open")
AssertEqual(gate.ApplyLine("Idle", 1000), "reset", "first known Idle resets routing sequence")
AssertEqual(gate.GetRouteDecision(true, 1001), "route", "fresh Idle routes media keys")
AssertEqual(gate.ApplyLine("Idle", 1200), "state", "repeated state does not request a reset")
AssertEqual(gate.ApplyLine(".", 2000), "heartbeat", "heartbeat refreshes detector freshness")
AssertEqual(gate.GetRouteDecision(true, 4999), "route", "fresh heartbeat keeps Idle routable")
AssertEqual(gate.GetRouteDecision(true, 5001), "reset-pass", "stale detector fails open and requests reset")
AssertEqual(gate.GetRouteDecision(true, 5002), "pass", "stale detector remains fail-open")

AssertEqual(gate.ApplyLine("Playing", 6000), "reset", "state recovery resets routing sequence")
AssertEqual(gate.GetRouteDecision(true, 6001), "pass", "Playing passes media keys through")
AssertEqual(gate.ApplyLine("Playing", 6100), "state", "repeated Playing does not reset sequence")
AssertEqual(gate.ApplyLine("Unknown", 6200), "reset", "Unknown requests a reset")
AssertEqual(gate.GetRouteDecision(true, 6201), "pass", "Unknown fails open")

AssertEqual(gate.ApplyLine("Idle", 7000), "reset", "Idle can recover after Unknown")
AssertEqual(gate.GetRouteDecision(false, 7001), "reset-pass", "dead detector process fails open")

smtc := SmtcCompatState(3000, 2000)
AssertEqual(smtc.HandleAction("next", true, 1000), "pending-next", "Idle SMTC Next starts a compensation cycle")
AssertEqual(smtc.HandleState("Playing", 1100), "compensate-next", "Next waits for playback before compensating")
AssertEqual(smtc.HandleAction("previous", false, 1150), "echo", "expected Previous echo is consumed exactly")
AssertEqual(smtc.HandleAction("pause", false, 1200), "echo", "expected Pause echo is consumed exactly")
AssertEqual(smtc.HandleState("Idle", 1250), "complete", "compensation completes when playback returns Idle")

AssertEqual(smtc.HandleAction("prev", true, 2000), "pending-prev", "Idle SMTC Prev starts a compensation cycle")
AssertEqual(smtc.HandleState("Playing", 2100), "compensate-prev", "Prev waits for playback before compensating")
AssertEqual(smtc.HandleAction("next", false, 2150), "echo", "expected Next echo is consumed exactly")
AssertEqual(smtc.HandleAction("pause", false, 2200), "echo", "second compensation Pause echo is consumed")
AssertEqual(smtc.HandleState("Idle", 2250), "complete", "Prev compensation returns to Idle")

AssertEqual(smtc.HandleAction("next", false, 3000), "ignore", "Playing SMTC actions are left to the player")
AssertEqual(smtc.HandleAction("play", true, 3100), "ignore", "Play/Pause actions do not enter the Next/Prev router")
AssertEqual(smtc.HandleAction("next", true, 4000), "pending-next", "new compensation cycle can start")
AssertEqual(smtc.Expire(7001), true, "stuck compensation cycle expires fail-open")
AssertEqual(smtc.HandleAction("next", true, 7100), "pending-next", "routing recovers after compensation timeout")
AssertEqual(smtc.HandleState("Unknown", 7200), "abort", "Unknown aborts SMTC compatibility state")


ExitApp(0)
