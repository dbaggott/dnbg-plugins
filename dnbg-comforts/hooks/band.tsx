import { atom, read, update } from 'claude-code'
import type { EngineInterface, On, PluginOptions } from 'claude-code'

import type { UsageLine } from '../types'
import { displayName, isModel, priceRank } from './models'
import { standardModel } from './options'
import { findPending } from './updates'

const usage = atom({ plugin: 'dnbg-comforts', key: 'usage' } as const, { model: null, figures: '', cache: null }, { shape: 'usage-2' })
// When the last turn ended; kept in state so a reload keeps the cache countdown.
const lastResponseAt = atom({ plugin: 'dnbg-comforts', key: 'lastResponseAt' } as const, null)
const compactThreshold = atom({ plugin: 'dnbg-comforts', key: 'compactThreshold' } as const, null)
const pendingUpdates = atom({ plugin: 'dnbg-comforts', key: 'pendingUpdates' } as const, [])

const REFRESH_MS = 15_000
// Assumed rather than read: the figures a mod can read carry no cache
// lifetime, and a subscription session gets an hour. Hence the `~`.
const CACHE_TTL_MS = 60 * 60 * 1000
const LIMIT_LABELS: Record<string, string> = { five_hour: 'session', seven_day: 'week' }

function span(ms: number): string {
  const minutes = Math.max(0, Math.round(ms / 60000))
  if (minutes < 60) return `${minutes}m`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h${String(minutes % 60).padStart(2, '0')}m`
  return `${Math.floor(hours / 24)}d${hours % 24}h`
}

async function measureThreshold($: EngineInterface): Promise<void> {
  // `summary` counts locally from the last response; it sends no request.
  const { context } = await $.session.usage({ breakdown: 'summary' })
  const threshold = context.breakdown?.autoCompactThreshold ?? null
  await update($, compactThreshold, () => threshold)
}

async function measure($: EngineInterface, standard: string): Promise<UsageLine> {
  const now = await $.clock.now()
  const figures = await $.session.usage()
  const model = await $.session.model()
  const parts: string[] = []

  const { percent, window } = figures.context
  if (percent !== undefined) {
    const threshold = await read($, compactThreshold)
    const compactsAt = threshold === null ? '' : ` (compacts at ${Math.round((threshold / window) * 100)}%)`
    parts.push(`context ${Math.round(percent)}%${compactsAt}`)
  }
  for (const limit of figures.rateLimits) {
    const label = LIMIT_LABELS[limit.kind] ?? limit.kind
    const reset = limit.resetsAt ? ` ↻${span(Date.parse(limit.resetsAt) - now)}` : ''
    parts.push(`${label} ${Math.round(limit.percentUsed)}%${reset}`)
  }
  // Usage windows are reported only on a subscription, where cost is moot.
  if (figures.rateLimits.length === 0 && figures.cost) parts.push(`$${figures.cost.usd.toFixed(2)}`)
  const updates = await read($, pendingUpdates)
  if (updates.length > 0) parts.push(`restart to update ${updates.join(', ')}`)

  const flag = isModel(model, standard)
    ? null
    : { name: displayName(model), isPricier: priceRank(model) > priceRank(standard) }

  const respondedAt = await read($, lastResponseAt)
  const left = respondedAt === null ? null : respondedAt + CACHE_TTL_MS - now
  const cache = left === null ? null : { minutesLeft: left > 0 ? Math.round(left / 60000) : null }

  return { model: flag, figures: parts.join(' · '), cache }
}

async function refresh($: EngineInterface, standard: string): Promise<void> {
  const line = await measure($, standard)
  await update($, usage, () => line)
}

export async function startBand($: EngineInterface, options: PluginOptions): Promise<void> {
  const standard = standardModel(options)
  const pending = await findPending($)
  await update($, pendingUpdates, () => pending)
  await measureThreshold($)
  await refresh($, standard)
  await $.clock.every(REFRESH_MS, () => void refresh($, standard))
}

export function registerBand(on: On, options: PluginOptions): void {
  const standard = standardModel(options)

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    const now = await $.clock.now()
    await update($, lastResponseAt, () => now)
    await measureThreshold($)
    await refresh($, standard)

    return done
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const line = await read($, usage)
    if (e.props.hasSurvey || (line.model === null && line.figures === '' && line.cache === null)) return next(e)

    const { Box, Text } = $.ui.resolve(e)

    return (
      <Box marginTop={1}>
        {line.model !== null &&
          (line.model.isPricier ? (
            <Text bold color="white" backgroundColor="red">{` ⚠ ${line.model.name} `}</Text>
          ) : (
            <Text bold color="white" backgroundColor="#5b8bd9">{` ${line.model.name} `}</Text>
          ))}
        {line.model !== null && line.figures !== '' && <Text dimColor>{'  '}</Text>}
        <Text dimColor>{line.figures}</Text>
        {line.cache !== null && line.figures !== '' && <Text dimColor>{' · '}</Text>}
        {line.cache !== null &&
          (line.cache.minutesLeft === null ? (
            // Cold: the next request re-sends the whole context uncached.
            <Text color="black" backgroundColor="yellow">{' cache ~cold '}</Text>
          ) : (
            <Text dimColor>{`cache ~warm ${span(line.cache.minutesLeft * 60000)}`}</Text>
          ))}
      </Box>
    )
  })
}
