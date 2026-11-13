import type { EngineInterface, Register } from 'claude-code'

import { onModelSwitch, registerBand, showSaved, startBand } from './band'
import { registerLater, startLater } from './later'
import { standardModel } from './options'
import { checkSavedModel, startSavedModel } from './saved-model'
import { registerTranscripts } from './transcripts'

// How long after a model switch to look at the settings file again, in case
// the saved model is written after the switch is reported.
const SETTLE_MS = 500

/** Announces a newly saved non-standard model; whether there was one. */
async function announceSaved($: EngineInterface, standard: string): Promise<boolean> {
  const saved = await checkSavedModel($, standard)
  if (saved !== null) await showSaved($, saved, standard)
  return saved !== null
}

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
    await onModelSwitch($, e.cache_ttl, standard)
    if (!(await announceSaved($, standard))) {
      await $.clock.sleep(SETTLE_MS)
      await announceSaved($, standard)
    }

    return result
  })

  // A save of the default model writes user settings; this catches it whatever
  // the order of the write and the switch.
  on('classic.ConfigChange', async ($, e, next) => {
    const result = await next(e)
    if (e.source === 'user_settings') await announceSaved($, standard)

    return result
  })

  registerLater(on)
  registerBand(on, options)
  registerTranscripts(on, options)
}
