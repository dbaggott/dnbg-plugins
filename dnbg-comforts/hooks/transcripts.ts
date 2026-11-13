import type { On, PluginOptions } from 'claude-code'

import { dataDir } from './options'

// Copies the transcript aside before each compaction, so the full
// conversation survives it: <data dir>/transcripts/<session id>/<time>.jsonl.
export function registerTranscripts(on: On, options: PluginOptions): void {
  on('classic.PreCompact', async ($, e, next) => {
    // A failed copy is reported and never stands in the compaction's way.
    try {
      const stamp = new Date(await $.clock.now()).toISOString().replace(/[:.]/g, '-')
      const directory = `${await dataDir($, options)}/transcripts/${e.session_id}`
      // A transcript can pass the 4 MiB that `$.fs.read` takes, so the host copies it.
      const made = await $.process.run(['mkdir', '-p', directory])
      const copied = made.exitCode === 0 ? await $.process.run(['cp', e.transcript_path, `${directory}/${stamp}.jsonl`]) : made
      if (copied.exitCode !== 0) throw new Error(copied.stderr.trim())
    } catch (error) {
      $.ui.toast(`Could not copy the transcript before compacting: ${error instanceof Error ? error.message : String(error)}`)
    }

    return next(e)
  })
}
