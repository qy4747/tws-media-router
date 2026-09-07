import { EventEmitter } from "node:events"
import fs from "node:fs"
import fsPromises from "node:fs/promises"
import os from "node:os"
import path from "node:path"

type PlayerState = "Playing" | "Idle" | "Unknown"
export type SmtcAction = "next" | "prev" | "play" | "pause"

const INITIAL_TAIL_BYTES = 1024 * 1024
const READ_CHUNK_BYTES = 64 * 1024
const HEARTBEAT_INTERVAL_MS = 1000

const HEADER = /^\[(\d+):(\d+):(\d{4}\/\d{6}:\d+):([A-Z]+):([a-zA-Z0-9._-]+)\((\d+)\)\]\s+\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]/
const EXIT = `【app】,{"actionId":"exitApp"}`
const TRACK_STARTS = [
  `【playing】,"checkPlayPrivilege",`,
  `【playing】,"playOneTrackInPlayingList"`,
]
const NATIVE_TRACK_START = `【playing】,"native播放资源load完成，开始播放"`
const PLAY_STATE = /【playing】,"native播放state",(\d+),/
const SMTC_FROM = /"from"\s*:\s*"smtc"/i
const SMTC_ACTION = /"action_type"\s*:\s*"play"/i
const SMTC_TYPE = /"type"\s*:\s*"(play|pause)"/i
const SMTC_POINT = /"action"\s*:\s*"_pc_smtc"/i
const SMTC_TRANSPORT_ACTION = /"action_type"\s*:\s*"(next|prev|previous)"/i

function isElogLine(line: string): boolean {
  return HEADER.test(line)
}

export function parseSmtcAction(line: string): SmtcAction | null {
  if (!isElogLine(line)) return null

  if (SMTC_POINT.test(line)) {
    const match = line.match(SMTC_TRANSPORT_ACTION)
    if (!match) return null
    return match[1].toLowerCase() === "next" ? "next" : "prev"
  }

  if (!SMTC_FROM.test(line) || !SMTC_ACTION.test(line)) return null
  const match = line.match(SMTC_TYPE)
  return match ? (match[1].toLowerCase() as "play" | "pause") : null
}

function parseSmtcState(line: string): PlayerState | null {
  if (!SMTC_FROM.test(line) || !SMTC_ACTION.test(line)) return null

  const match = line.match(SMTC_TYPE)
  if (!match) return null

  return match[1].toLowerCase() === "pause" ? "Idle" : "Playing"
}

export function parseState(line: string): PlayerState | null {
  if (!isElogLine(line)) return null
  if (line.includes(EXIT)) return "Idle"

  const nativeMatch = line.match(PLAY_STATE)
  if (nativeMatch) return Number(nativeMatch[1]) === 2 ? "Idle" : "Playing"

  return parseSmtcState(line)
}

export function deriveInitialPlayState(lines: string[]): PlayerState {
  const records: string[] = []
  let hasTrack = false

  for (let index = lines.length - 1; index >= 0; index -= 1) {
    const line = lines[index].trim()
    if (!isElogLine(line)) continue

    records.unshift(line)
    if (line.includes(EXIT)) return "Idle"

    if (parseSmtcState(line)) {
      hasTrack = true
      break
    }

    if (TRACK_STARTS.some((marker) => line.includes(marker))) {
      hasTrack = true
      break
    }

    if (line.includes(NATIVE_TRACK_START)) hasTrack = true
  }

  if (!hasTrack) return "Unknown"

  let state: PlayerState = "Playing"
  for (const line of records) state = parseState(line) ?? state
  return state
}

export function decodeElogBytes(data: Uint8Array): Uint8Array {
  const decoded = new Uint8Array(data.length)

  for (let index = 0; index < data.length; index += 1) {
    const byte = data[index]
    const high = (Math.floor(byte / 16) ^ ((byte % 16) + 8)) % 16
    decoded[index] = high * 16 + Math.floor(byte / 64) * 4 + (~Math.floor(byte / 16) & 3)
  }

  return decoded
}

export function decodeElog(data: Uint8Array): string {
  return new TextDecoder("utf-8").decode(decodeElogBytes(data))
}

export function splitUtf8Lines(
  pending: Uint8Array,
  chunk: Uint8Array
): { lines: string[]; pending: Uint8Array } {
  const combined = new Uint8Array(pending.length + chunk.length)
  combined.set(pending)
  combined.set(chunk, pending.length)

  const lines: string[] = []
  let lineStart = 0

  for (let index = 0; index < combined.length; index += 1) {
    if (combined[index] !== 0x0a) continue

    let lineEnd = index
    if (lineEnd > lineStart && combined[lineEnd - 1] === 0x0d) lineEnd -= 1
    lines.push(new TextDecoder("utf-8").decode(combined.subarray(lineStart, lineEnd)))
    lineStart = index + 1
  }

  return { lines, pending: combined.slice(lineStart) }
}

export class NeteasePlayStateDetector extends EventEmitter {
  private readonly filePath = path.join(
    process.env.LOCALAPPDATA ?? path.join(os.homedir(), "AppData", "Local"),
    "NetEase",
    "CloudMusic",
    "cloudmusic.elog"
  )

  private fileSize = 0
  private observedSize = 0
  private state: PlayerState | null = null
  private pendingBytes = new Uint8Array()
  private reading = false
  private readAgain = false
  private heartbeatTimer: NodeJS.Timeout | null = null

  private readonly watchListener = (current: fs.Stats) => {
    this.observedSize = current.size
    this.readAgain = true
    void this.drainChanges()
  }

  public async start(): Promise<void> {
    try {
      const stats = await fsPromises.stat(this.filePath)
      const initial = await this.readInitialTail(stats.size)

      this.fileSize = stats.size
      this.observedSize = stats.size
      this.pendingBytes = new Uint8Array(initial.pendingBytes)
      this.emitState(initial.state, true)

      fs.watchFile(this.filePath, { interval: 300 }, this.watchListener)
      this.heartbeatTimer = setInterval(() => this.emit("heartbeat"), HEARTBEAT_INTERVAL_MS)

      const current = await fsPromises.stat(this.filePath)
      this.observedSize = current.size
      if (current.size !== this.fileSize) {
        this.readAgain = true
        void this.drainChanges()
      }
    } catch (error) {
      this.stop()
      throw error
    }
  }

  public stop(): void {
    fs.unwatchFile(this.filePath, this.watchListener)
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer)
    this.heartbeatTimer = null
  }

  private async readInitialTail(fileSize: number): Promise<{
    state: PlayerState
    pendingBytes: Uint8Array
  }> {
    const start = Math.max(0, fileSize - INITIAL_TAIL_BYTES)
    const length = fileSize - start
    const encoded = Buffer.alloc(length)
    const handle = await fsPromises.open(this.filePath, "r")

    try {
      let offset = 0
      while (offset < length) {
        const { bytesRead } = await handle.read(encoded, offset, length - offset, start + offset)
        if (bytesRead === 0) throw new Error("NetEase elog changed while reading initial state")
        offset += bytesRead
      }
    } finally {
      await handle.close()
    }

    const split = splitUtf8Lines(new Uint8Array(), decodeElogBytes(encoded))
    const hadCompleteLine = split.lines.length > 0
    const lines = start > 0 ? split.lines.slice(1) : split.lines.slice()
    const pendingIsAligned = start === 0 || hadCompleteLine
    const pendingBytes = pendingIsAligned ? split.pending : new Uint8Array()

    if (pendingIsAligned && pendingBytes.length > 0) {
      lines.push(new TextDecoder("utf-8").decode(pendingBytes))
    }

    return { state: deriveInitialPlayState(lines), pendingBytes }
  }

  private async drainChanges(): Promise<void> {
    if (this.reading) return
    this.reading = true
    let failed = false

    try {
      while (this.readAgain || this.observedSize !== this.fileSize) {
        this.readAgain = false
        const targetSize = this.observedSize

        if (targetSize < this.fileSize) {
          this.fileSize = 0
          this.pendingBytes = new Uint8Array()
          this.emitState("Unknown")
        }

        if (targetSize > this.fileSize) {
          const start = this.fileSize
          const result = await this.readRange(start, targetSize, this.pendingBytes)
          this.pendingBytes = new Uint8Array(result.pendingBytes)
          this.fileSize = targetSize
          for (const event of result.events) {
            if (event.kind === "action") this.emit("action", event.value)
            else this.emitState(event.value)
          }
        }
      }
    } catch {
      failed = true
      this.emitState("Unknown")
    } finally {
      this.reading = false
      if (!failed && this.readAgain) void this.drainChanges()
    }
  }

  private async readRange(
    start: number,
    endExclusive: number,
    initialPending: Uint8Array
  ): Promise<{
    events: Array<
      | { kind: "action"; value: SmtcAction }
      | { kind: "state"; value: PlayerState }
    >
    pendingBytes: Uint8Array
  }> {
    const handle = await fsPromises.open(this.filePath, "r")
    const buffer = Buffer.allocUnsafe(READ_CHUNK_BYTES)
    const events: Array<
      | { kind: "action"; value: SmtcAction }
      | { kind: "state"; value: PlayerState }
    > = []
    let pendingBytes = new Uint8Array(initialPending)
    let position = start

    try {
      while (position < endExclusive) {
        const length = Math.min(buffer.length, endExclusive - position)
        const { bytesRead } = await handle.read(buffer, 0, length, position)
        if (bytesRead === 0) throw new Error("NetEase elog changed while reading appended data")

        const decoded = decodeElogBytes(buffer.subarray(0, bytesRead))
        const split = splitUtf8Lines(pendingBytes, decoded)
        pendingBytes = new Uint8Array(split.pending)

        for (const line of split.lines) {
          const trimmed = line.trim()
          const action = parseSmtcAction(trimmed)
          if (action) events.push({ kind: "action", value: action })

          const state = parseState(trimmed)
          if (state) events.push({ kind: "state", value: state })
        }

        position += bytesRead
      }
    } finally {
      await handle.close()
    }

    return { events, pendingBytes }
  }

  private emitState(state: PlayerState, force = false): void {
    if (!force && state === this.state) return
    this.state = state
    this.emit("state", state)
  }
}
