import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import { parseIni, parseProviderSettings } from "../build/config.js"

function createRouter() {
  let nextPosition = 0
  let prevPosition = 0

  return {
    next() {
      prevPosition = 0
      nextPosition = nextPosition % 3 + 1
      return nextPosition <= 2 ? "transcription shortcut" : "enter"
    },
    prev() {
      prevPosition = prevPosition % 2 + 1
      if (prevPosition === 1) nextPosition = 0
      return prevPosition === 1 ? "reset next position" : "clear input"
    },
    stateChanged() {
      nextPosition = 0
      prevPosition = 0
    },
  }
}

test("default config preserves the verified shortcut and state machine", async () => {
  const text = await readFile(new URL("../config/router.ini", import.meta.url), "utf8")
  const config = parseIni(text)
  const provider = parseProviderSettings(text)
  const router = createRouter()

  assert.equal(config.actions, undefined)
  assert.deepEqual(provider, { provider: "netease", gsmtcPollIntervalMs: 500 })
  assert.equal(config.detector.poll_interval_ms, "100")
  assert.equal(config.transcription_shortcut.press, "{LCtrl down}{LAlt down}{Up down}")
  assert.equal(config.transcription_shortcut.release, "{Up up}{LAlt up}{LCtrl up}")
  assert.equal(config.transcription_shortcut.hold_ms, "50")
  assert.equal(config.clear.select, "^a")
  assert.equal(config.clear.delete, "{Backspace}")

  assert.deepEqual([router.next(), router.next(), router.next(), router.next()], ["transcription shortcut", "transcription shortcut", "enter", "transcription shortcut"])
  assert.equal(router.prev(), "reset next position")
  assert.equal(router.next(), "transcription shortcut")
  assert.equal(router.prev(), "reset next position")
  assert.equal(router.prev(), "clear input")
  router.next()
  router.next()
  router.stateChanged()
  assert.equal(router.next(), "transcription shortcut")
  assert.equal(router.prev(), "reset next position")
})

test("rejects unsupported providers", () => {
  assert.throws(() => parseProviderSettings("[player]\nprovider=auto"), /Unsupported/)
})
