import { EventEmitter } from "node:events"
import fs from "node:fs"
import fsPromises from "node:fs/promises"
import os from "node:os"
import path from "node:path"

type PlayerState = "Playing" | "Idle" | "Unknown"

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

  if (!hasTrack) return "Idle"

  let state: PlayerState = "Playing"
  for (const line of records) state = parseState(line) ?? state
  return state
}

export function decodeElog(data: Uint8Array): string {
  const decoded = data.map((byte) => {
    const high = (Math.floor(byte / 16) ^ ((byte % 16) + 8)) % 16
    return high * 16 + Math.floor(byte / 64) * 4 + (~Math.floor(byte / 16) & 3)
  })

  return new TextDecoder("utf-8").decode(decoded)
}

export class NeteasePlayStateDetector extends EventEmitter {
  private readonly filePath = path.join(
    process.env.LOCALAPPDATA ?? path.join(os.homedir(), "AppData", "Local"),
    "NetEase",
    "CloudMusic",
    "cloudmusic.elog"
  )

  private fileSize = 0
  private state: PlayerState | null = null

  private readonly watchListener = (current: fs.Stats) => {
    if (current.size < this.fileSize) {
      this.fileSize = 0
      return
    }

    const stream = fs.createReadStream(this.filePath, { start: this.fileSize })
    stream.on("data", (chunk) => {
      const data = typeof chunk === "string" ? Buffer.from(chunk) : chunk
      for (const line of decodeElog(new Uint8Array(data)).split("\n")) {
        const next = parseState(line.trim())
        if (next && next !== this.state) {
          this.state = next
          this.emit("state", next)
        }
      }
    })
    this.fileSize = current.size
  }

  public async start(): Promise<void> {
    await fsPromises.access(this.filePath)
    const buffer = await fsPromises.readFile(this.filePath)

    this.fileSize = buffer.length
    this.state = deriveInitialPlayState(decodeElog(buffer).split("\n"))
    fs.watchFile(this.filePath, { interval: 300 }, this.watchListener)
    this.emit("state", this.state)
  }

  public stop(): void {
    fs.unwatchFile(this.filePath, this.watchListener)
  }
}
