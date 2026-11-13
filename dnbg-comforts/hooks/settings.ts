import type { EngineInterface } from 'claude-code'

import { home } from './options'

/** Claude Code's user config directory: `CLAUDE_CONFIG_DIR`, else `~/.claude`. */
export async function configDir($: EngineInterface): Promise<string> {
  return (await $.env.get('CLAUDE_CONFIG_DIR')) || `${await home($)}/.claude`
}

export async function readJson($: EngineInterface, path: string): Promise<unknown> {
  try {
    return JSON.parse(await $.fs.read(path))
  } catch {
    return undefined
  }
}
