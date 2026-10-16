import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

// Turns that end without a single tool call, in a row. A goal loop that keeps
// the model talking while it does nothing costs the person money and moves
// nothing; this counts such turns and tells the next one, in its system
// prompt, that it must act or ask.
const idleTurns = atom({ plugin: 'smartgoal', key: 'idleTurns' } as const, 0)

const RULE = `## The no-idle rule (smartgoal)

The previous turn took no action: it called no tool. A turn that only reports
status ("nothing changed", "still holding", "still waiting") is forbidden. This
turn does exactly one of these:

1. Takes a concrete step with a tool that changes or learns something: install
   or try a tool, read a file or document not yet read, run one experiment on
   one case, or reread CLAUDE.md and the design (diagrams included) and say
   what was misread.
2. Asks the person one question whose answer unblocks the work, with two to
   four concrete options, and ends.

If neither is possible, say so in one sentence, name the decision that is
needed, and end. Never repeat a message already sent.`

export const register: Register = on => {
  let tools = 0

  // the main loop's turns only: a subagent's run is work, not a reply
  on('turn.start', ($, e, next) => {
    if (!e.agentId) tools = 0
    return next(e)
  })

  // counts and passes every call through; a failure here never blocks one
  on('tool.call', ($, e, next) => {
    tools += 1
    return next(e)
  }).catch(($, e, next) => next(e))

  on('turn.complete', async ($, e, next) => {
    if (e.agentId) return next(e)
    const idle = tools === 0 && e.reason === 'answer'
    const n = await update($, idleTurns, k => (idle ? k + 1 : 0))
    if (n >= 2) {
      $.ui.toast(`smartgoal: ${n} turns in a row took no action. If a goal is set, /goal clear stops the loop.`)
    }
    return next(e)
  })

  on('prompt.compose', async ($, e, next) => {
    const composed = await next(e)
    if ((await read($, idleTurns)) === 0) {
      return composed
    }
    return {
      ...composed,
      sections: [...composed.sections, { id: 'smartgoal:no-idle', text: RULE, scope: 'session' }],
    }
  })
}
