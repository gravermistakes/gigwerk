import { test, expect } from 'claude-code/testing'

const input = { model: 'm', promptModel: 'm', surfaces: [], tools: [], outputStyle: null, traits: [] }
const base = { sections: [{ id: 'intro', text: 'base', scope: 'shared' as const }] }

test('a turn that called no tool puts the no-idle rule into the next prompt', async ($, on) => {
  on('prompt.compose', () => base)
  on('turn.complete', () => ({ text: '' }))
  await $.turn.complete({ reason: 'answer', answer: 'nothing changed', durationMs: 1, isAborted: false, turnId: 't1' } as never)
  const r = await $.prompt.compose(input)
  expect(r.sections.some(s => s.id === 'smartgoal:no-idle')).toBe(true)
})

test('with no idle turn, the prompt is left as it was', async ($, on) => {
  on('prompt.compose', () => base)
  const r = await $.prompt.compose(input)
  expect(r.sections.some(s => s.id === 'smartgoal:no-idle')).toBe(false)
})
