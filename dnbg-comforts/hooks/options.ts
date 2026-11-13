import type { EngineInterface, PluginOptions } from 'claude-code'

const DEFAULT_STANDARD_MODEL = 'opus'
const DEFAULT_DATA_DIR = '~/.claude/dnbg'
const SAFE_PATH = /^(\/|~\/)[A-Za-z0-9._\/-]*$/

export function standardModel(options: PluginOptions): string {
  const value = options.standard_model
  return typeof value === 'string' && value.trim() !== '' ? value.trim() : DEFAULT_STANDARD_MODEL
}

export async function home($: EngineInterface): Promise<string> {
  const value = await $.env.get('HOME')
  if (!value) throw new Error('HOME is not set')
  return value
}

/** The data directory, `~` expanded; a value outside SAFE_PATH falls back to the default. */
export async function dataDir($: EngineInterface, options: PluginOptions): Promise<string> {
  const value = options.data_dir
  const chosen = typeof value === 'string' && SAFE_PATH.test(value) && !value.split('/').includes('..') ? value : DEFAULT_DATA_DIR
  return chosen.startsWith('~/') ? `${await home($)}${chosen.slice(1)}` : chosen
}
