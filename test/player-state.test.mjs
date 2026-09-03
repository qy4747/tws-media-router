import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import { normalizeGsmtcStatus } from "../build/providers/gsmtc.js"

test("normalizes GSMTC playback states conservatively", () => {
  assert.equal(normalizeGsmtcStatus("Playing"), "Playing")
  assert.equal(normalizeGsmtcStatus("Paused"), "Idle")
  assert.equal(normalizeGsmtcStatus("Stopped"), "Idle")
  assert.equal(normalizeGsmtcStatus("Closed"), "Idle")
  assert.equal(normalizeGsmtcStatus("Opened"), "Unknown")
  assert.equal(normalizeGsmtcStatus("Changing"), "Unknown")
  assert.equal(normalizeGsmtcStatus("NoSession"), "Unknown")
  assert.equal(normalizeGsmtcStatus("Error"), "Unknown")
})

test("AHK protocol makes Unknown fail open", async () => {
  const ahk = await readFile(new URL("../automation/tws-media-router.ahk", import.meta.url), "utf8")
  assert.match(ahk, /else if line = "Unknown"[\s\S]*?DetectorReady := false/)
  assert.match(ahk, /return DetectorReady && DetectorPid && ProcessExist\(DetectorPid\) && !CloudMusicPlaying/)
})

