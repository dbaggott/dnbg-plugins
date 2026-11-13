import type { CommandRunInput, On, SessionContextBreakdown, SessionUsage } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

const BAND = {
  plugin: 'dnbg-comforts',
  component: 'AbovePrompt',
  surface: 'terminal',
  props: { hasSurvey: false, isWorking: false, isCollapsed: false, maxRows: 10, bodyColumns: 120, scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const

const HOME = '/home/u'
const SETTINGS = `${HOME}/.claude/settings.json`

// A /later typed at the prompt.
function later(args: string): CommandRunInput {
  return { command: 'later', args, origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 120 } }
}

const SWITCH = { from_model: 'claude-opus-5-5', to_model: 'claude-sonnet-5-5', requested_model: 'sonnet', source: 'command', context_tokens: 0, prompt_cache_warm: true, cache_ttl: '1h', estimated_cache_write_usd: 0, pricing: 'catalog' } as const

const NOW = Date.parse('2026-01-01T00:00:00Z')

// The engine beneath the plugin: a subscription session on `model`.
const SUBSCRIPTION: SessionUsage = {
  startedAt: 0,
  context: { tokens: 50_000, window: 200_000, percent: 25, breakdown: { autoCompactThreshold: 190_000 } as SessionContextBreakdown },
  rateLimits: [{ kind: 'seven_day', percentUsed: 21, resetsAt: '2026-01-05T00:00:00Z' }],
  cost: { usd: 4.2 },
}

function world(on: On, model: string, files: Record<string, string> = {}, usage: SessionUsage = SUBSCRIPTION, reads = { usage: 0 }) {
  const clock = mock.clock(on, { now: NOW })
  mock.store(on)
  mock.env(on, { HOME })
  on('command.register', () => ({ value: { command: 'later' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('fs.read', (_, e) => (e.path in files ? { value: files[e.path] as string } : { deny: 'missing' }))
  on('session.model', () => ({ value: model }))
  on('session.usage', () => (reads.usage++, { value: usage }))
  // Stands for the engine's own empty band.
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })

  return clock
}

test('/later answers locally and hands the note to the model', async ($, on) => {
  world(on, 'claude-opus-5-5')

  const ran = await $.command.run(later('option B, no rush'))

  expect(ran.text).toBe('Queued for Claude’s next turn.')
  expect(ran.context?.[0]).toContain('option B, no rush')
})

test('/later with no note says how to use it', async ($, on) => {
  world(on, 'claude-opus-5-5')

  const ran = await $.command.run(later('  '))

  expect(ran.text).toBe('Usage: /later <note>')
  expect(ran.context).toBeUndefined()
})

test('on the standard model the band shows only the figures, cost left out', async ($, on) => {
  world(on, 'claude-opus-5-5')
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  const ui = await $.ui.mount(BAND)
  const texts = (await ui.findAll({ type: 'Text' })).map(text => text.text).join('|')

  expect(texts).toContain('context 25% (compacts at 95%)')
  expect(texts).toContain('week 21% ↻4d0h')
  // Cache sits beside context, before the windows that arrive later.
  expect(texts.indexOf('cache')).toBeGreaterThan(texts.indexOf('context'))
  expect(texts.indexOf('cache')).toBeLessThan(texts.indexOf('week'))
  expect(texts).not.toContain('$4.20')
  expect(texts).not.toContain('OPUS')
  await ui.unmount()
})

test('a pricier model is flagged with a warning badge', async ($, on) => {
  world(on, 'claude-fable-5-2')
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount(BAND)
  expect((await ui.find({ type: 'Text', text: /FABLE/ }))?.text).toBe(' ⚠ FABLE 5.2 ')
  await ui.unmount()
})

test('a cheaper model is named without the warning', async ($, on) => {
  world(on, 'claude-sonnet-5-5')
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount(BAND)
  expect((await ui.find({ type: 'Text', text: /SONNET/ }))?.text).toBe(' SONNET 5.5 ')
  await ui.unmount()
})

test('saving a non-standard model for future sessions says so once, in a toast and the band', async ($, on) => {
  const files: Record<string, string> = { [SETTINGS]: '{"model":"opus"}' }
  const clock = world(on, 'claude-opus-5-5', files)
  const toasts: { text: string; timeoutMs?: number }[] = []
  on('ui.toast', (_, e) => (toasts.push({ text: e.text, timeoutMs: e.timeoutMs }), { value: undefined }))
  on('classic.PostModelSwitch', () => ({}))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  files[SETTINGS] = '{"model":"fable"}'
  await $.classic.PostModelSwitch({ ...SWITCH, to_model: 'claude-fable-5-2', requested_model: 'fable' })
  await $.classic.PostModelSwitch(SWITCH)

  expect(toasts).toEqual([{ text: 'FYI: you set your model to fable for all future sessions.', timeoutMs: 12_000 }])
  const ui = await $.ui.mount(BAND)
  const block = await ui.find({ type: 'Text', text: /saved/ })
  expect(block?.text).toBe(' saved: FABLE ')
  expect(block?.props.backgroundColor).toBe('red')
  await ui.unmount()

  await clock.advance(31_000)
  const later = await $.ui.mount(BAND)
  expect(await later.find({ type: 'Text', text: /saved/ })).toBeUndefined()
  await later.unmount()
})

test('the cache counts down after a turn and turns yellow once cold', async ($, on) => {
  const clock = world(on, 'claude-opus-5-5')
  on('turn.complete', () => ({ text: '' }))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })

  const warm = await $.ui.mount(BAND)
  expect((await warm.find({ type: 'Text', text: /cache/ }))?.text).toBe('cache ~warm 1h00m')
  await warm.unmount()

  await clock.advance(61 * 60 * 1000)
  const cold = await $.ui.mount(BAND)
  const badge = await cold.find({ type: 'Text', text: /cache/ })
  expect(badge?.text).toBe(' cache ~cold ')
  expect(badge?.props.backgroundColor).toBe('yellow')
  await cold.unmount()
})

test('a new session shows no cost before its first response', async ($, on) => {
  world(on, 'claude-opus-5-5', {}, { startedAt: 0, context: { window: 200_000 }, rateLimits: [], cost: { usd: 0 } })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  const ui = await $.ui.mount(BAND)
  expect((await ui.find({ type: 'Text', text: /\$/ }))?.text).toBeUndefined()
  await ui.unmount()
})


test('a dated or suffixed model id reads as its family and version', async ($, on) => {
  world(on, 'claude-haiku-4-5-20251001[1m]')
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount(BAND)
  expect((await ui.find({ type: 'Text', text: /HAIKU/ }))?.text).toBe(' HAIKU 4.5 ')
  await ui.unmount()
})

test('another model of the standard family is named without a cost colour', { options: { standard_model: 'claude-opus-5-5' } }, async ($, on) => {
  world(on, 'claude-opus-4-1')
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount(BAND)
  const name = await ui.find({ type: 'Text', text: /OPUS/ })
  expect(name?.text).toBe('OPUS 4.1')
  expect(name?.props.backgroundColor).toBeUndefined()
  await ui.unmount()
})

test('a model switch leaves the cache cold', async ($, on) => {
  world(on, 'claude-opus-5-5')
  on('turn.complete', () => ({ text: '' }))
  on('classic.PostModelSwitch', () => ({}))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
  await $.classic.PostModelSwitch(SWITCH)

  const ui = await $.ui.mount(BAND)
  expect((await ui.find({ type: 'Text', text: /cache/ }))?.text).toBe(' cache ~cold ')
  await ui.unmount()
})

test('saving the standard model by its alias is not news when the standard is a full id', { options: { standard_model: 'claude-opus-5-5' } }, async ($, on) => {
  const files: Record<string, string> = { [SETTINGS]: '{"model":"sonnet"}' }
  world(on, 'claude-opus-5-5', files)
  const notes: string[] = []
  on('ui.toast', (_, e) => (notes.push(e.text), { value: undefined }))
  on('classic.PostModelSwitch', () => ({}))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  files[SETTINGS] = '{"model":"opus"}'
  await $.classic.PostModelSwitch(SWITCH)

  expect(notes).toEqual([])
})

test('before compacting, the transcript is copied under the data directory', async ($, on) => {
  world(on, 'claude-opus-5-5')
  const runs: string[][] = []
  on('process.run', (_, e) => (runs.push([...e.argv]), { value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  on('classic.PreCompact', () => ({}))

  await $.classic.PreCompact({ trigger: 'auto', custom_instructions: null, session_id: 's1', transcript_path: '/t/s1.jsonl' })

  expect(runs[0]).toEqual(['mkdir', '-p', `${HOME}/.claude/dnbg/transcripts/s1`])
  expect(runs[1]?.slice(0, 2)).toEqual(['cp', '/t/s1.jsonl'])
  expect(runs[1]?.[2]).toMatch(/^\/home\/u\/\.claude\/dnbg\/transcripts\/s1\/2026-01-01T00-00-00-000Z\.jsonl$/)
})

test('a copy that cannot run is reported, and the compaction goes ahead', async ($, on) => {
  world(on, 'claude-opus-5-5')
  const toasts: string[] = []
  let compacted = false
  on('process.run', () => {
    throw new Error('spawn mkdir ENOENT')
  })
  on('ui.toast', (_, e) => (toasts.push(e.text), { value: undefined }))
  on('classic.PreCompact', () => ((compacted = true), {}))

  await $.classic.PreCompact({ trigger: 'auto', custom_instructions: null, session_id: 's1', transcript_path: '/t/s1.jsonl' })

  expect(compacted).toBe(true)
  expect(toasts[0]).toContain('Could not copy the transcript before compacting')
})

test('saving the model the session runs on marks its badge instead of repeating it', async ($, on) => {
  const files: Record<string, string> = { [SETTINGS]: '{"model":"opus"}' }
  world(on, 'claude-fable-5-2', files)
  on('ui.toast', () => ({ value: undefined }))
  on('classic.PostModelSwitch', () => ({}))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  files[SETTINGS] = '{"model":"fable"}'
  await $.classic.PostModelSwitch({ ...SWITCH, to_model: 'claude-fable-5-2', requested_model: 'fable' })

  const ui = await $.ui.mount(BAND)
  const blocks = (await ui.findAll({ type: 'Text', text: /FABLE/ })).map(text => text.text)
  expect(blocks).toEqual([' ⚠ FABLE 5.2 · saved '])
  await ui.unmount()
})

test('a new session shows context 0% and no cache yet, so the band keeps its shape', async ($, on) => {
  world(on, 'claude-opus-5-5', {}, { startedAt: 0, context: { window: 200_000 }, rateLimits: [], cost: { usd: 0 } })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  const ui = await $.ui.mount(BAND)
  // Newer engines also hand back the stand-in's own text; the band's is the rest.
  const texts = (await ui.findAll({ type: 'Text' }))
    .map(text => text.text)
    .filter(text => text !== 'engine')
    .join('')
  expect(texts).toBe('context 0% · cache none')
  await ui.unmount()
})

test('a headless session does no band work after a turn', async ($, on) => {
  const reads = { usage: 0 }
  world(on, 'claude-opus-5-5', {}, SUBSCRIPTION, reads)
  on('turn.complete', () => ({ text: '' }))
  await $.session.start({ cwd: '/', surface: null, isInteractive: false })
  await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })

  expect(reads.usage).toBe(0)
})
