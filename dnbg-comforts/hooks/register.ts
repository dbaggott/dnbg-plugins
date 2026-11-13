import type { Register } from 'claude-code'

import { onModelSwitch, registerBand, startBand } from './band'
import { registerLater, startLater } from './later'
import { standardModel } from './options'
import { onSavedModelSwitch, startSavedModel } from './saved-model'
import { registerTranscripts } from './transcripts'

export const register: Register = (on, options) => {
  const standard = standardModel(options)

  // One hook per event for the module: the engine takes no second.
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await startLater($)
    await startSavedModel($)
    // Headless runs draw no band.
    if (e.isInteractive) await startBand($, options)

    return started
  })

  on('classic.PostModelSwitch', async ($, e, next) => {
    const result = await next(e)
    await onSavedModelSwitch($, standard)
    await onModelSwitch($, e.cache_ttl, standard)

    return result
  })

  registerLater(on)
  registerBand(on, options)
  registerTranscripts(on, options)
}
