import type { EngineInterface, On } from 'claude-code'

export async function startLater($: EngineInterface): Promise<void> {
  await $.command.register({
    name: 'later',
    description: 'Leave Claude a note it reads on its next turn, without starting one',
    argumentHint: '<note>',
    immediate: true,
  })
}

export function registerLater(on: On): void {
  on('command.run', { command: 'later' }, ($, e) => {
    const note = e.args.trim()
    if (note === '') return { text: 'Usage: /later <note>' }

    return {
      text: 'Queued for Claude’s next turn.',
      context: [`A note the user left for you with /later (not urgent; answer it when it suits the work): ${note}`],
    }
  })
}
