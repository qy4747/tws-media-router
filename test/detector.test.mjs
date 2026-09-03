import assert from "node:assert/strict"
import test from "node:test"
import {
  deriveInitialPlayState,
  splitUtf8Lines,
} from "../build/detector/netease-play-state.js"

const row = (message) =>
  `[1:2:2025/123456:789:INFO:player.cpp(7)] [2026-09-03 12:00:00] ${message}`

test("derives Unknown without reliable NetEase playback evidence", () => {
  const track = row(`【playing】,"checkPlayPrivilege",{}`)
  const pause = row(`【playing】,"native播放state",2,`)
  const play = row(`【playing】,"native播放state",1,`)

  assert.equal(deriveInitialPlayState([]), "Unknown")
  assert.equal(deriveInitialPlayState([row("unrecognized playback log")]), "Unknown")
  assert.equal(deriveInitialPlayState([track]), "Playing")
  assert.equal(deriveInitialPlayState([track, pause]), "Idle")
  assert.equal(deriveInitialPlayState([track, pause, play]), "Playing")
  assert.equal(deriveInitialPlayState([track, row(`【app】,{"actionId":"exitApp"}`)]), "Idle")
})

test("preserves partial UTF-8 lines across arbitrary chunks", () => {
  const bytes = new TextEncoder().encode("A你B\r\nC")
  const first = splitUtf8Lines(new Uint8Array(), bytes.slice(0, 2))
  assert.deepEqual(first.lines, [])

  const second = splitUtf8Lines(first.pending, bytes.slice(2))
  assert.deepEqual(second.lines, ["A你B"])
  assert.equal(new TextDecoder().decode(second.pending), "C")
})
