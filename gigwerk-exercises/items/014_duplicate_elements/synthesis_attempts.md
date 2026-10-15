# Synthesis attempt record

The runtime was invoked at most twice for synthesis, each under `timeout -k 2s 60s`. Neither invocation produced a candidate.

| Attempt | Exit code | Elapsed seconds | `stdout` | `stderr` | Disposition |
|---|---:|---:|---|---|---|
| 1 | 1 | 0.020424 | `contract.sq:11:16: Parse Error: Unexpected 15-column indentation or ':'; expecting top-level indentation (started at line 6) or end of input` | empty | Rejected before synthesis. The named-argument syntax was not accepted by this local parser. |
| 2 | 1 | 0.021376 | `contract.sq:11:34: Parse Error: Unexpected '='; expecting operator or '}'` | empty | Rejected before synthesis. Local `Tokens.hs` identifies Synquid equality as `==`; this was corrected in the retained contract after attempt 2. |

`synthesis.out`, `synthesis.err`, `synthesis.status`, and `synthesis.elapsed` retain the direct artifacts from attempt 2. The contract was **not** submitted for a third synthesis attempt, in accordance with the two-attempt cap.
