import { atom, read, update } from 'claude-code'
import type { EngineInterface } from 'claude-code'

import { isModel } from './models'
import { configDir, readJson } from './settings'

// The saved model this session last saw. Session state: another session's
// view of the settings file must not stand in for this one's.
const lastSaved = atom({ plugin: 'dnbg-comforts', key: 'lastSaved' } as const, '')

/** The `model` saved in user settings for future sessions; '' when none is. */
async function savedModel($: EngineInterface): Promise<string> {
  const settings = await readJson($, `${await configDir($)}/settings.json`)
  const model = (settings as { model?: unknown } | undefined)?.model
  return typeof model === 'string' ? model : ''
}

export async function startSavedModel($: EngineInterface): Promise<void> {
  const saved = await savedModel($)
  await update($, lastSaved, () => saved)
}

/**
 * Says so when the model saved for future sessions changed to a non-standard
 * one. A switch for this session only leaves the saved model as it was, so
 * comparing against the last one seen tells the two apart.
 */
export async function onSavedModelSwitch($: EngineInterface, standard: string): Promise<void> {
  const saved = await savedModel($)
  const previous = await read($, lastSaved)
  await update($, lastSaved, () => saved)

  if (saved !== previous && saved !== '' && !isModel(saved, standard)) {
    const message = `FYI: you set your model to ${saved} for all future sessions.`
    // The toast first: it shows in every session, the notification only
    // where the terminal takes one.
    $.ui.toast(message)
    await $.ui.notify(message, { title: 'Claude Code' })
  }
}
