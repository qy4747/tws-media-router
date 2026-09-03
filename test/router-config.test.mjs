import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import { parseIni, parseProviderSettings } from "../build/config.js"

function createRouter(nextActions, prevActions) {
  let nextPosition = 0
  let prevPosition = 0

  const advance = (actions, position) => [position % actions.length + 1, actions[position % actions.length]]

  return {
    next() {
      prevPosition = 0
      const [position, action] = advance(nextActions, nextPosition)
      nextPosition = position
      return action
    },
    prev() {
      const [position, action] = advance(prevActions, prevPosition)
      prevPosition = position
      if (action === "reset") nextPosition = 0
      return action
    },
    stateChanged() {
      nextPosition = 0
      prevPosition = 0
    },
  }
}

test("default config preserves the verified action state machine", async () => {
  const text = await readFile(new URL("../config/router.ini", import.meta.url), "utf8")
  const config = parseIni(text)
  const provider = parseProviderSettings(text)
  const next = config.actions.next.split(",")
  const prev = config.actions.prev.split(",")
  const router = createRouter(next, prev)

  assert.deepEqual(next, ["voice", "voice", "enter"])
  assert.deepEqual(prev, ["reset", "clear"])
  assert.deepEqual(provider, { provider: "netease", gsmtcPollIntervalMs: 500 })
  assert.equal(config.detector.poll_interval_ms, "100")
  assert.equal(config.voice.press, "{LCtrl down}{LAlt down}{Up down}")
  assert.equal(config.voice.release, "{Up up}{LAlt up}{LCtrl up}")
  assert.equal(config.voice.hold_ms, "50")
  assert.equal(config.clear.select, "^a")
  assert.equal(config.clear.delete, "{Backspace}")

  assert.deepEqual([router.next(), router.next(), router.next(), router.next()], ["voice", "voice", "enter", "voice"])
  assert.equal(router.prev(), "reset")
  assert.equal(router.next(), "voice")
  assert.equal(router.prev(), "reset")
  assert.equal(router.prev(), "clear")
  router.next()
  router.next()
  router.stateChanged()
  assert.equal(router.next(), "voice")
  assert.equal(router.prev(), "reset")
})

test("rejects unsupported providers", () => {
  assert.throws(() => parseProviderSettings("[player]\nprovider=auto"), /Unsupported/)
})
