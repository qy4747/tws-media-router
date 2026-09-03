import assert from "node:assert/strict"
import test from "node:test"
import { deriveInitialPlayState } from "../build/detector/netease-play-state.js"

const row = (message) =>
  `[1:2:2025/123456:789:INFO:player.cpp(7)] [2026-09-03 12:00:00] ${message}`

test("derives only Playing or Idle from the latest track session", () => {
  const track = row(`【playing】,"checkPlayPrivilege",{}`)
  const pause = row(`【playing】,"native播放state",2,`)
  const play = row(`【playing】,"native播放state",1,`)

  assert.equal(deriveInitialPlayState([]), "Idle")
  assert.equal(deriveInitialPlayState([track]), "Playing")
  assert.equal(deriveInitialPlayState([track, pause]), "Idle")
  assert.equal(deriveInitialPlayState([track, pause, play]), "Playing")
  assert.equal(deriveInitialPlayState([track, row(`【app】,{"actionId":"exitApp"}`)]), "Idle")
})
