#Requires AutoHotkey v2.0
#Include %A_ScriptDir%\..\automation\router-state.ahk

AssertEqual(actual, expected, message) {
    if actual != expected
        throw Error(message " (expected=" expected ", actual=" actual ")")
}

router := RouterState()
AssertEqual(router.CommandActive, false, "router starts outside a command session")
AssertEqual(router.Next(), "voice-start", "first Next starts transcription")
AssertEqual(router.CommandActive, true, "first Next owns the command session")
AssertEqual(router.Next(), "voice-stop", "second Next stops transcription")
AssertEqual(router.CommandActive, true, "second Next keeps command ownership until send")
AssertEqual(router.Next(), "enter", "third Next sends Enter")
AssertEqual(router.CommandActive, false, "third Next closes the command session")
AssertEqual(router.Next(), "voice-start", "Next sequence loops without a time window")
AssertEqual(router.CommandActive, true, "new Next cycle opens a new command session")

router.Reset()
AssertEqual(router.Prev(1001), "reset", "first Prev resets Next sequence")
AssertEqual(router.CommandActive, true, "first Prev opens command ownership for the clear sequence")
AssertEqual(router.Prev(1001), "clear", "second Prev clears in the same window")
AssertEqual(router.CommandActive, false, "second Prev closes the command session")

router.Reset()
AssertEqual(router.Prev(1001), "reset", "first Prev records active window")
AssertEqual(router.Prev(2002), "cancel", "window change cancels destructive clear")
AssertEqual(router.Prev(2002), "reset", "cancelled clear starts a new Prev sequence")

router.Reset()
router.Next()
router.Next()
router.Reset()
AssertEqual(router.Next(), "voice-start", "state reset restarts Next sequence")
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
AssertEqual(gate.GetRouteDecision(true, 6001, true), "route", "healthy active command can route while Playing")
AssertEqual(gate.ApplyLine("Playing", 6100), "state", "repeated Playing does not reset sequence")
AssertEqual(gate.ApplyLine("Unknown", 6200), "reset", "Unknown requests a reset")
AssertEqual(gate.GetRouteDecision(true, 6201, true), "pass", "Unknown still fails open even for an active command")

AssertEqual(gate.ApplyLine("Idle", 7000), "reset", "Idle can recover after Unknown")
AssertEqual(gate.GetRouteDecision(false, 7001), "reset-pass", "dead detector process fails open")

smtc := SmtcCompatState(1500, 750)
AssertEqual(smtc.HandleAction("next", true, 1000), "route-next", "Idle SMTC Next opens guard and routes immediately")
AssertEqual(smtc.GuardActive, true, "guard is active after Idle Next")
AssertEqual(smtc.HandleState("Playing", 1050), "compensate-prev", "Next queues Previous compensation once playback starts")
smtc.Expect(["prev", "pause"], 1060)
AssertEqual(smtc.HandleAction("previous", false, 1100), "echo", "self Previous echo is consumed")
AssertEqual(smtc.HandleAction("pause", false, 1150), "echo", "self Pause echo is consumed")
AssertEqual(smtc.HandleState("Idle", 1200), "settled", "compensation reports settled when playback returns Idle")

retry := SmtcCompatState(1500, 750)
AssertEqual(retry.HandleAction("next", true, 5000), "route-next", "retry scenario opens guard")
AssertEqual(retry.HandleState("Playing", 5050), "compensate-prev", "retry scenario starts restore")
retry.Expect(["prev", "pause"], 5060)
AssertEqual(retry.HandleState("Playing", 5070), "guard", "repeated Playing is ignored while compensation has no Pause acknowledgement")
AssertEqual(retry.HandleAction("prev", false, 5080), "echo", "restore echo is consumed before Pause")
AssertEqual(retry.HandleAction("pause", false, 5090), "echo", "Pause acknowledgement is recorded")
AssertEqual(retry.HandleState("Playing", 5100), "force-pause", "Playing after acknowledged Pause is forced back to Pause")
retry.Expect(["pause"], 5110)
AssertEqual(retry.HandleAction("pause", false, 5120), "echo", "forced Pause acknowledgement is consumed")
AssertEqual(retry.HandleState("Idle", 5130), "settled", "successful retry reports settled Idle")

AssertEqual(smtc.HandleAction("next", false, 1300), "route-next", "a second Next routes even during transient non-idle guard state")
AssertEqual(smtc.GuardDeadlineTick, 2800, "user Next refreshes the sliding guard deadline")
AssertEqual(smtc.HandleAction("play", false, 1350), "force-pause", "Play inside the guard is converted to Pause")
AssertEqual(smtc.Expire(2799), false, "guard remains active before inactivity deadline")
AssertEqual(smtc.Expire(2801), true, "guard expires after inactivity window")
AssertEqual(smtc.GuardActive, false, "expired guard returns to normal mode")

AssertEqual(smtc.HandleAction("next", false, 3000), "ignore", "Playing Next cannot start a new guard")
AssertEqual(smtc.HandleAction("prev", true, 4000), "route-prev", "Idle Prev can start a new guard")
AssertEqual(smtc.HandleState("Unknown", 4100), "abort", "Unknown aborts the guard fail-open")
AssertEqual(smtc.GuardActive, false, "Unknown clears guard state")


ExitApp(0)
