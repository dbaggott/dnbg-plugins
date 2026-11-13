import type { EngineInterface, On, PluginOptions } from 'claude-code'

import { isModel } from './models'
import { standardModel } from './options'
import { configDir, readJson } from './settings'

const STORE_KEY = 'savedModel'

/** The `model` saved in user settings for future sessions; '' when none is. */
async function savedModel($: EngineInterface): Promise<string> {
  const settings = await readJson($, `${await configDir($)}/settings.json`)
  const model = (settings as { model?: unknown } | undefined)?.model
  return typeof model === 'string' ? model : ''
}

export async function startSavedModel($: EngineInterface): Promise<void> {
  await $.store.set(STORE_KEY, await savedModel($))
}

export function registerSavedModel(on: On, options: PluginOptions): void {
  const standard = standardModel(options)

  // A switch for this session only leaves the saved model as it was, so
  // comparing against the last one seen tells the two apart.
  on('classic.PostModelSwitch', async ($, e, next) => {
    const result = await next(e)
    const saved = await savedModel($)
    const previous = await $.store.get(STORE_KEY)
    await $.store.set(STORE_KEY, saved)

    if (saved !== previous && saved !== '' && !isModel(saved, standard)) {
      const message = `FYI: you set your model to ${saved} for all future sessions.`
      await $.ui.notify(message, { title: 'Claude Code' })
      $.ui.toast(message)
    }

    return result
  })
}
