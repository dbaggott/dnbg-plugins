import type { Register } from 'claude-code'

import { registerBand, startBand } from './band'
import { registerLater, startLater } from './later'
import { registerSavedModel, startSavedModel } from './saved-model'
import { registerTranscripts } from './transcripts'

export const register: Register = (on, options) => {
  // One session.start for the module: the engine takes one per event.
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await startLater($)
    await startSavedModel($)
    await startBand($, options)

    return started
  })

  registerLater(on)
  registerBand(on, options)
  registerSavedModel(on, options)
  registerTranscripts(on, options)
}
