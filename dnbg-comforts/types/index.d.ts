/** A model other than the standard one, as the usage band flags it, by its family's price against the standard's. */
export type ModelFlag = { name: string; cost: 'more' | 'same' | 'less'; isJustSaved?: boolean }

/** The prompt cache's estimated state: none before the first turn, then warm with minutes left, or cold. */
export type CacheState = { kind: 'none' } | { kind: 'warm'; minutesLeft: number } | { kind: 'cold' }

/** Drawn in this order: model, a just-saved model, context, cache, then the rest (usage windows, cost, updates). */
export type UsageLine = { model: ModelFlag | null; saved: ModelFlag | null; context: string; cache: CacheState; rest: string }

/** A model just saved for future sessions, shown in the band until `until`. */
export type SavedNotice = ModelFlag & { model: string; until: number }

declare module 'claude-code' {
  interface PluginState {
    'dnbg-comforts': {
      usage: Shaped<UsageLine>
      lastResponseAt: number | null
      compactThreshold: number | null
      pendingUpdates: string[]
      cacheTtlMs: number | null
      lastSaved: string
      savedNotice: SavedNotice | null
    }
  }
}
