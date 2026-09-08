import fs from "node:fs"
import fsPromises from "node:fs/promises"
import os from "node:os"
import path from "node:path"
import {
  decodeElogBytes,
  parseSmtcAction,
  parseState,
  splitUtf8Lines,
} from "../build/detector/netease-play-state.js"

const outputPath = process.argv[2]
if (!outputPath) throw new Error("Usage: node diagnostics/smtc-elog-monitor.mjs <output.log>")

const elogPath = path.join(
  process.env.LOCALAPPDATA ?? path.join(os.homedir(), "AppData", "Local"),
  "NetEase",
  "CloudMusic",
  "cloudmusic.elog"
)

let fileSize = (await fsPromises.stat(elogPath)).size
let pending = new Uint8Array()
let reading = false

function write(kind, detail) {
  fs.appendFileSync(outputPath, String(Date.now()) + "|elog_" + kind + "|" + detail + "\n", "utf8")
}

async function poll() {
  if (reading) return
  reading = true

  try {
    const stats = await fsPromises.stat(elogPath)

    if (stats.size < fileSize) {
      fileSize = stats.size
      pending = new Uint8Array()
      write("meta", "truncated")
      return
    }

    if (stats.size === fileSize) return

    const start = fileSize
    const length = stats.size - start
    const buffer = Buffer.allocUnsafe(length)
    const handle = await fsPromises.open(elogPath, "r")

    try {
      let offset = 0
      while (offset < length) {
        const { bytesRead } = await handle.read(buffer, offset, length - offset, start + offset)
        if (bytesRead === 0) break
        offset += bytesRead
      }
    } finally {
      await handle.close()
    }

    fileSize = stats.size
    const split = splitUtf8Lines(pending, decodeElogBytes(buffer))
    pending = new Uint8Array(split.pending)

    for (const rawLine of split.lines) {
      const line = rawLine.trim()
      const action = parseSmtcAction(line)
      const state = parseState(line)

      if (action) write("action", action)
      if (state) write("state", state)

      const button = line.match(/\[SMTCWrapper\] Button pressed:\s*(\d+)/i)
      if (button) write("button", button[1])
    }
  } catch (error) {
    write("error", error instanceof Error ? error.message : String(error))
  } finally {
    reading = false
  }
}

const timer = setInterval(() => void poll(), 20)

function stop() {
  clearInterval(timer)
  process.exit(0)
}

process.on("SIGINT", stop)
process.on("SIGTERM", stop)
write("meta", "started")
