import type { EngineInterface } from 'claude-code'

import { configDir, readJson } from './settings'

type Installed = { plugins?: Record<string, { scope?: string; version?: string }[]> }
type Catalog = { plugins?: { name?: string; source?: unknown }[] }

/**
 * Plugins whose marketplace copy on disk is newer than the installed one:
 * auto-update fetched it, and only a fresh start activates it. Catalog
 * entries whose source is not a path inside the marketplace are skipped.
 */
export async function findPending($: EngineInterface): Promise<string[]> {
  const plugins = `${await configDir($)}/plugins`
  const installed = (await readJson($, `${plugins}/installed_plugins.json`)) as Installed | undefined
  const pending: string[] = []

  for (const [id, installs] of Object.entries(installed?.plugins ?? {})) {
    const [name, marketplace] = id.split('@')
    // The user-scope install is the one every session loads.
    const version = (installs.find(install => install.scope === 'user') ?? installs[0])?.version
    if (!name || !marketplace || !version) continue

    const root = `${plugins}/marketplaces/${marketplace}`
    const catalog = (await readJson($, `${root}/.claude-plugin/marketplace.json`)) as Catalog | undefined
    const source = catalog?.plugins?.find(entry => entry.name === name)?.source
    if (typeof source !== 'string' || !source.startsWith('./')) continue

    const manifest = (await readJson($, `${root}/${source.slice(2)}/.claude-plugin/plugin.json`)) as { version?: string } | undefined
    if (manifest?.version && manifest.version !== version) pending.push(name)
  }

  return pending
}
