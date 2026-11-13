/** A model other than the standard one, as the usage band flags it. */
export type ModelFlag = { name: string; isPricier: boolean }

/** The prompt cache's estimated state: minutes left while warm, null once cold. */
export type CacheState = { minutesLeft: number | null }

export type UsageLine = { model: ModelFlag | null; figures: string; cache: CacheState | null }

declare module 'claude-code' {
  interface PluginState {
    'dnbg-comforts': {
      usage: Shaped<UsageLine>
      lastResponseAt: number | null
      compactThreshold: number | null
      pendingUpdates: string[]
    }
  }
}
