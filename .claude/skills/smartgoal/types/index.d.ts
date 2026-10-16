/** Consecutive turns that ended without a single tool call. */
export type IdleTurns = number

declare module 'claude-code' {
  interface PluginState {
    smartgoal: { idleTurns: IdleTurns }
  }
}
