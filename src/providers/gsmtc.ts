import { EventEmitter } from "node:events"
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process"

type PlayerState = "Playing" | "Idle" | "Unknown"

export function normalizeGsmtcStatus(status: string): PlayerState {
  switch (status.trim()) {
    case "Playing":
      return "Playing"
    case "Paused":
    case "Stopped":
    case "Closed":
      return "Idle"
    default:
      return "Unknown"
  }
}

export class GsmtcProvider extends EventEmitter {
  private child: ChildProcessWithoutNullStreams | null = null
  private buffer = ""
  private state: PlayerState | null = null
  private stopping = false

  public constructor(
    private readonly helperPath: string,
    private readonly pollIntervalMs: number
  ) {
    super()
  }

  public start(): Promise<void> {
    this.stopping = false
    this.child = spawn(
      "powershell.exe",
      [
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        this.helperPath,
        "-PollIntervalMs",
        String(this.pollIntervalMs),
      ],
      { windowsHide: true }
    )

    this.child.stdout.setEncoding("utf8")
    this.child.stdout.on("data", (chunk: string) => this.readOutput(chunk))
    this.child.once("exit", () => {
      this.child = null
      if (!this.stopping) this.emitState("Unknown")
    })

    return new Promise((resolve, reject) => {
      this.child?.once("spawn", resolve)
      this.child?.once("error", reject)
    })
  }

  public stop(): void {
    this.stopping = true
    this.child?.kill()
    this.child = null
  }

  private readOutput(chunk: string): void {
    this.buffer += chunk
    const lines = this.buffer.split(/\r?\n/)
    this.buffer = lines.pop() ?? ""

    for (const line of lines) this.emitState(normalizeGsmtcStatus(line))
  }

  private emitState(state: PlayerState): void {
    if (state === this.state) return
    this.state = state
    this.emit("state", state)
  }
}
