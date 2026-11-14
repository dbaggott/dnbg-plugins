import { atom, read, update } from 'claude-code'
import type { EngineInterface, On, PluginOptions } from 'claude-code'

import type { CacheState, ModelFlag, UsageLine } from '../types'
import { costAgainst, displayName, isModel } from './models'
import { standardModel } from './options'
import { findPending } from './updates'

const usage = atom({ plugin: 'dnbg-comforts', key: 'usage' } as const, { model: null, saved: null, context: 'context 0%', cache: { kind: 'none' }, rest: '' }, { shape: 'usage-6' })
// When the last turn ended; kept in state so a reload keeps the cache countdown.
const lastResponseAt = atom({ plugin: 'dnbg-comforts', key: 'lastResponseAt' } as const, null)
const compactThreshold = atom({ plugin: 'dnbg-comforts', key: 'compactThreshold' } as const, null)
const pendingUpdates = atom({ plugin: 'dnbg-comforts', key: 'pendingUpdates' } as const, [])
// Set once the band starts; a headless session never starts it. Held with the
// code rather than in `$.state`, which a /clear starts over while the band's timer runs on.
let isBandOn = false
const savedNotice = atom({ plugin: 'dnbg-comforts', key: 'savedNotice' } as const, null)
const SAVED_NOTICE_MS = 30_000
const SAVED_LABEL = ' · all future sessions!'
// The cache lifetime a model switch reported; until one does, it is assumed.
const cacheTtlMs = atom({ plugin: 'dnbg-comforts', key: 'cacheTtlMs' } as const, null)

const REFRESH_MS = 15_000
const HOUR_MS = 60 * 60 * 1000
const FIVE_MINUTES_MS = 5 * 60 * 1000
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

  // Before the first response nothing has been sent, so 0% is the true reading.
  const { percent = 0, window } = figures.context
  const threshold = await read($, compactThreshold)
  const compactsAt = threshold === null ? '' : ` (compacts at ${Math.round((threshold / window) * 100)}%)`
  const context = `context ${Math.round(percent)}%${compactsAt}`
  for (const limit of figures.rateLimits) {
    const label = LIMIT_LABELS[limit.kind] ?? limit.kind
    const reset = limit.resetsAt ? ` ↻${span(Date.parse(limit.resetsAt) - now)}` : ''
    parts.push(`${label} ${Math.round(limit.percentUsed)}%${reset}`)
  }
  // Usage windows are reported only on a subscription, where cost is moot. Before
  // the first response neither has a reading, so a zero cost says nothing.
  if (figures.rateLimits.length === 0 && figures.cost && figures.cost.usd > 0) parts.push(`$${figures.cost.usd.toFixed(2)}`)
  const updates = await read($, pendingUpdates)
  if (updates.length > 0) parts.push(`restart to update ${updates.join(', ')}`)

  const flag = isModel(model, standard)
    ? null
    : { name: displayName(model), cost: costAgainst(model, standard) }

  // Unreported, the lifetime is assumed from the plan: an hour on a subscription
  // (usage windows reported), five minutes otherwise. Hence the `~`.
  const ttl = (await read($, cacheTtlMs)) ?? (figures.rateLimits.length > 0 ? HOUR_MS : FIVE_MINUTES_MS)
  const respondedAt = await read($, lastResponseAt)
  const left = respondedAt === null ? null : respondedAt + ttl - now
  const cache: CacheState =
    left === null ? { kind: 'none' } : left > 0 ? { kind: 'warm', minutesLeft: Math.round(left / 60000) } : { kind: 'cold' }

  const notice = await read($, savedNotice)
  const isNoticeUp = notice !== null && now < notice.until
  // The model just saved is usually the one running: one block says both.
  if (isNoticeUp && flag !== null && isModel(model, notice.model)) {
    return { model: { ...flag, isJustSaved: true }, saved: null, context, cache, rest: parts.join(' · ') }
  }
  const saved: ModelFlag | null = isNoticeUp ? { name: notice.name, cost: notice.cost } : null

  return { model: flag, saved, context, cache, rest: parts.join(' · ') }
}

async function refresh($: EngineInterface, standard: string): Promise<void> {
  const line = await measure($, standard)
  await update($, usage, () => line)
}

async function checkUpdates($: EngineInterface): Promise<void> {
  const pending = await findPending($)
  await update($, pendingUpdates, () => pending)
}

/** Marks `saved` as just saved for future sessions, in the band, for a while. */
export async function showSaved($: EngineInterface, saved: string, standard: string): Promise<void> {
  if (!isBandOn) return
  const until = (await $.clock.now()) + SAVED_NOTICE_MS
  await update($, savedNotice, () => ({ model: saved, name: displayName(saved), cost: costAgainst(saved, standard), until }))
  await refresh($, standard)
}

/** A model switch forfeits the cache: the next request writes it afresh. */
export async function onModelSwitch($: EngineInterface, ttl: '5m' | '1h', standard: string): Promise<void> {
  if (!isBandOn) return
  await update($, cacheTtlMs, () => (ttl === '1h' ? HOUR_MS : FIVE_MINUTES_MS))
  await update($, lastResponseAt, current => (current === null ? null : 0))
  await refresh($, standard)
}

export async function startBand($: EngineInterface, options: PluginOptions): Promise<void> {
  const standard = standardModel(options)
  isBandOn = true
  await checkUpdates($)
  await measureThreshold($)
  await refresh($, standard)
  // A failed refresh leaves the last figures up and is logged; the next one retries.
  await $.clock.every(REFRESH_MS, () => {
    refresh($, standard).catch(error => $.ui.log(`usage band refresh failed: ${String(error)}`))
  })
}

export function registerBand(on: On, options: PluginOptions): void {
  const standard = standardModel(options)

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (!isBandOn) return done

    try {
      const now = await $.clock.now()
      await update($, lastResponseAt, () => now)
      // Auto-update can land the marketplace copy after session start.
      await checkUpdates($)
      await measureThreshold($)
      await refresh($, standard)
    } catch (error) {
      $.ui.log(`usage band refresh failed: ${String(error)}`)
    }

    return done
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const line = await read($, usage)
    if (e.props.hasSurvey) return next(e)

    const { Box, Text } = $.ui.resolve(e)

    return (
      <Box marginTop={1}>
        {line.model?.cost === 'more' && <Text bold color="white" backgroundColor="red">{` ⚠ ${line.model.name}${line.model.isJustSaved ? SAVED_LABEL : ''} `}</Text>}
        {line.model?.cost === 'less' && <Text bold color="white" backgroundColor="#5b8bd9">{` ${line.model.name}${line.model.isJustSaved ? SAVED_LABEL : ''} `}</Text>}
        {line.model?.cost === 'same' && <Text bold>{`${line.model.name}${line.model.isJustSaved ? SAVED_LABEL : ''}`}</Text>}
        {line.model !== null && line.saved !== null && <Text>{' '}</Text>}
        {line.saved?.cost === 'more' && <Text bold color="white" backgroundColor="red">{` ${line.saved.name}${SAVED_LABEL} `}</Text>}
        {line.saved?.cost === 'less' && <Text bold color="white" backgroundColor="#5b8bd9">{` ${line.saved.name}${SAVED_LABEL} `}</Text>}
        {line.saved?.cost === 'same' && <Text bold>{`${line.saved.name}${SAVED_LABEL}`}</Text>}
        {(line.model !== null || line.saved !== null) && <Text dimColor>{'  '}</Text>}
        <Text dimColor>{`${line.context} · `}</Text>
        {line.cache.kind === 'none' && <Text dimColor>cache none</Text>}
        {line.cache.kind === 'warm' && <Text dimColor>{`cache ~warm ${span(line.cache.minutesLeft * 60000)}`}</Text>}
        {/* Cold: the next request re-sends the whole context uncached. */}
        {line.cache.kind === 'cold' && <Text color="black" backgroundColor="yellow">{' cache ~cold '}</Text>}
        {line.rest !== '' && <Text dimColor>{` · ${line.rest}`}</Text>}
      </Box>
    )
  })
}
