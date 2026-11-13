/** A model other than the standard one, as the usage band flags it. */
export type ModelFlag = { name: string; isPricier: boolean }

export type UsageLine = { model: ModelFlag | null; figures: string }

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
