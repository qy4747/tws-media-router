import assert from "node:assert/strict"
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
