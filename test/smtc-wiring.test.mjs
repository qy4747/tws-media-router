import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

test("SMTC wiring preserves detector freshness and restore direction", async () => {
  const ahk = await readFile(new URL("../automation/tws-media-router.ahk", import.meta.url), "utf8")

  assert.match(
    ahk,
    /if line = "\." \{\s+Detector\.ApplyLine\(line, tick\)/,
    "heartbeat must refresh DetectorGate before the loop continues"
  )
  assert.match(
    ahk,
    /if result = "compensate-next"\s+SetTimer\(PerformSmtcRestoreNext, -1\)/,
    "compensate-next must send a real Media_Next restore"
  )
  assert.match(
    ahk,
    /else if result = "compensate-prev"\s+SetTimer\(PerformSmtcRestorePrev, -1\)/,
    "compensate-prev must send a real Media_Prev restore"
  )
  assert.match(
    ahk,
    /PerformSmtcRestorePrev\(\)[\s\S]*?Expect\(\["prev", "pause"\][\s\S]*?SendInput\("\{Media_Prev\}"\)/,
    "Previous restore must expect and send Previous"
  )
  assert.match(
    ahk,
    /PerformSmtcRestoreNext\(\)[\s\S]*?Expect\(\["next", "pause"\][\s\S]*?SendInput\("\{Media_Next\}"\)/,
    "Next restore must expect and send Next"
  )
})

test("NetEase raw observations are forwarded separately from deduplicated state", async () => {
  const detector = await readFile(
    new URL("../src/detector/netease-play-state.ts", import.meta.url),
    "utf8"
  )
  const index = await readFile(new URL("../src/index.ts", import.meta.url), "utf8")

  assert.match(detector, /this\.emit\("observation", event\.value\)\s+this\.emitState\(event\.value\)/)
  assert.match(index, /provider\.on\("observation",[\s\S]*?console\.log\(`OBS:\$\{state\}`\)/)
})

test("active command ownership survives Playing without weakening fail-open", async () => {
  const ahk = await readFile(new URL("../automation/tws-media-router.ahk", import.meta.url), "utf8")

  assert.match(
    ahk,
    /GetRouteDecision\(pidAlive, A_TickCount, Router\.CommandActive\)/,
    "routing must allow a healthy active command to continue while Playing"
  )
  assert.match(
    ahk,
    /suppressReset := \(SmtcCompat\.GuardActive \|\| Router\.CommandActive\) && line != "Unknown"/,
    "Playing and Idle transitions must not reset an active command session"
  )
})
