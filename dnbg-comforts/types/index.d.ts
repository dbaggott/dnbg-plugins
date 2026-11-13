/** A model other than the standard one, as the usage band flags it, by its family's price against the standard's. */
export type ModelFlag = { name: string; cost: 'more' | 'same' | 'less' }

/** The prompt cache's estimated state: none before the first turn, then warm with minutes left, or cold. */
export type CacheState = { kind: 'none' } | { kind: 'warm'; minutesLeft: number } | { kind: 'cold' }

export type UsageLine = { model: ModelFlag | null; figures: string; cache: CacheState }

declare module 'claude-code' {
  interface PluginState {
    'dnbg-comforts': {
      usage: Shaped<UsageLine>
      lastResponseAt: number | null
      compactThreshold: number | null
      pendingUpdates: string[]
      cacheTtlMs: number | null
      lastSaved: string
      isBandOn: boolean
    }
  }
}
