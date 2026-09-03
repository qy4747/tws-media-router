import { EventEmitter } from "node:events"
import fs from "node:fs"
import fsPromises from "node:fs/promises"
import os from "node:os"
import path from "node:path"

type PlayerState = "Playing" | "Idle" | "Unknown"

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

function isElogLine(line: string): boolean {
  return HEADER.test(line)
}

function parseState(line: string): PlayerState | null {
  if (!isElogLine(line)) return null
  if (line.includes(EXIT)) return "Idle"

  const match = line.match(PLAY_STATE)
  return match ? (Number(match[1]) === 2 ? "Idle" : "Playing") : null
}

export function deriveInitialPlayState(lines: string[]): PlayerState {
  const records: string[] = []
  let hasTrack = false

  for (let index = lines.length - 1; index >= 0; index -= 1) {
    const line = lines[index].trim()
    if (!isElogLine(line)) continue

    records.unshift(line)
    if (line.includes(EXIT)) return "Idle"

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
    const stats = await fsPromises.stat(this.filePath)
    const initial = await this.readInitialTail(stats.size)

    this.fileSize = stats.size
    this.observedSize = stats.size
    this.pendingBytes = initial.pendingBytes
    this.emitState(initial.state, true)

    fs.watchFile(this.filePath, { interval: 300 }, this.watchListener)
    this.heartbeatTimer = setInterval(() => this.emit("heartbeat"), HEARTBEAT_INTERVAL_MS)

    const current = await fsPromises.stat(this.filePath)
    this.observedSize = current.size
    if (current.size !== this.fileSize) {
      this.readAgain = true
      void this.drainChanges()
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
          this.pendingBytes = result.pendingBytes
          this.fileSize = targetSize
          for (const state of result.states) this.emitState(state)
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
  ): Promise<{ states: PlayerState[]; pendingBytes: Uint8Array }> {
    const handle = await fsPromises.open(this.filePath, "r")
    const buffer = Buffer.allocUnsafe(READ_CHUNK_BYTES)
    const states: PlayerState[] = []
    let pendingBytes = initialPending.slice()
    let position = start

    try {
      while (position < endExclusive) {
        const length = Math.min(buffer.length, endExclusive - position)
        const { bytesRead } = await handle.read(buffer, 0, length, position)
        if (bytesRead === 0) throw new Error("NetEase elog changed while reading appended data")

        const decoded = decodeElogBytes(buffer.subarray(0, bytesRead))
        const split = splitUtf8Lines(pendingBytes, decoded)
        pendingBytes = split.pending

        for (const line of split.lines) {
          const state = parseState(line.trim())
          if (state) states.push(state)
        }

        position += bytesRead
      }
    } finally {
      await handle.close()
    }

    return { states, pendingBytes }
  }

  private emitState(state: PlayerState, force = false): void {
    if (!force && state === this.state) return
    this.state = state
    this.emit("state", state)
  }
}
