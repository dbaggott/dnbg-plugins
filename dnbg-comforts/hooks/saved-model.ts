import { atom, read, update } from 'claude-code'
import type { EngineInterface } from 'claude-code'

import { isModel } from './models'
import { configDir, readJson } from './settings'

const TOAST_MS = 12_000

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
 * one, and returns that model; null when there is nothing to say. A switch for this session only leaves the saved model as it was, so
 * comparing against the last one seen tells the two apart.
 */
export async function checkSavedModel($: EngineInterface, standard: string): Promise<string | null> {
  const saved = await savedModel($)
  const previous = await read($, lastSaved)
  await update($, lastSaved, () => saved)

  if (saved !== previous && saved !== '' && !isModel(saved, standard)) {
    $.ui.toast(`FYI: you set your model to ${saved} for all future sessions.`, { timeoutMs: TOAST_MS })
    return saved
  }

  return null
}
