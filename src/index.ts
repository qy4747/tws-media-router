import { readFile } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { parseProviderSettings } from "./config.js"
import { NeteasePlayStateDetector } from "./detector/netease-play-state.js"
import { GsmtcProvider } from "./providers/gsmtc.js"

const projectDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const settings = parseProviderSettings(
  await readFile(path.join(projectDir, "config", "router.ini"), "utf8")
)

const provider =
  settings.provider === "netease"
    ? new NeteasePlayStateDetector()
    : new GsmtcProvider(
        path.join(projectDir, "helpers", "gsmtc-state.ps1"),
        settings.gsmtcPollIntervalMs
      )

provider.on("state", (state) => {
  console.log(state)
})

try {
  await provider.start()
} catch (error) {
  console.log("Unknown")
  console.error(error instanceof Error ? error.message : String(error))
  process.exitCode = 1
}
