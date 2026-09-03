export type ProviderName = "netease" | "gsmtc"

export type ProviderSettings = {
  provider: ProviderName
  gsmtcPollIntervalMs: number
}

export function parseIni(text: string): Record<string, Record<string, string>> {
  const config: Record<string, Record<string, string>> = {}
  let section: Record<string, string> | undefined

  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim()
    if (!line || line.startsWith(";")) continue

    const header = line.match(/^\[([^\]]+)]$/)
    if (header) {
      section = config[header[1]] = {}
      continue
    }

    const separator = line.indexOf("=")
    if (!section || separator < 1) throw new Error(`Invalid INI line: ${line}`)
    section[line.slice(0, separator).trim()] = line.slice(separator + 1).trim()
  }

  return config
}

export function parseProviderSettings(text: string): ProviderSettings {
  const player = parseIni(text).player ?? {}
  const provider = player.provider ?? "netease"
  const pollInterval = player.gsmtc_poll_interval_ms ?? "500"

  if (provider !== "netease" && provider !== "gsmtc") {
    throw new Error(`Unsupported player provider: ${provider}`)
  }

  if (!/^\d+$/.test(pollInterval) || Number(pollInterval) < 100) {
    throw new Error("player.gsmtc_poll_interval_ms must be at least 100")
  }

  return { provider, gsmtcPollIntervalMs: Number(pollInterval) }
}
