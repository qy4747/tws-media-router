import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import { parseIni, parseProviderSettings } from "../build/config.js"

test("default config preserves the verified environment settings", async () => {
  const text = await readFile(new URL("../config/router.ini", import.meta.url), "utf8")
  const config = parseIni(text)
  const provider = parseProviderSettings(text)

  assert.equal(config.actions, undefined)
  assert.deepEqual(provider, { provider: "netease", gsmtcPollIntervalMs: 500 })
  assert.equal(config.detector.poll_interval_ms, "100")
  assert.equal(config.detector.stale_after_ms, "3000")
  assert.equal(config.transcription_shortcut.press, "{LCtrl down}{LAlt down}{Up down}")
  assert.equal(config.transcription_shortcut.release, "{Up up}{LAlt up}{LCtrl up}")
  assert.equal(config.transcription_shortcut.hold_ms, "50")
  assert.equal(config.clear.select, "^a")
  assert.equal(config.clear.delete, "{Backspace}")
})

test("rejects unsupported providers", () => {
  assert.throws(() => parseProviderSettings("[player]\nprovider=auto"), /Unsupported/)
})

test("ignores irrelevant GSMTC settings for NetEase", () => {
  assert.deepEqual(
    parseProviderSettings("[player]\nprovider=netease\ngsmtc_poll_interval_ms=invalid"),
    { provider: "netease", gsmtcPollIntervalMs: 500 }
  )
})

test("validates GSMTC polling only when GSMTC is selected", () => {
  assert.throws(
    () => parseProviderSettings("[player]\nprovider=gsmtc\ngsmtc_poll_interval_ms=99"),
    /at least 100/
  )
  assert.deepEqual(
    parseProviderSettings("[player]\nprovider=gsmtc\ngsmtc_poll_interval_ms=750"),
    { provider: "gsmtc", gsmtcPollIntervalMs: 750 }
  )
})
