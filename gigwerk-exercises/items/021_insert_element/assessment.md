# Assessment — 021 Insert an Element at a Given Position Into a List

## Status

| Field | Value |
|---|---|
| Contract status | **ambiguous** |
| Specification strength | **partial** |
| Synthesis status | **not attempted** |
| Actual synthesis elapsed time | **0 seconds** |
| Final implementation authored | **No** |

## Evidence retained

The authoritative file was read through the GitHub Contents API at pinned commit `7b4c04b90b5433050bcecb25772880bc48bae4d0` (blob `f32f84b83e22f2b2b05571ce43d7b9d05b48a9c0`). It has one `## Solution` heading. Only the text before that heading was retained and inspected.

That permitted text is front matter only. It establishes the title and this description:

> Insert an element at a specified position (0-based index) within a list.

## Why no `contract.sq` exists

A full contract must state a callable interface and behavior for every input class. The permitted source does not declare:

1. an OCaml function name;
2. an exact signature or argument order;
3. whether index `length list` is valid append behavior;
4. negative/out-of-range behavior; or
5. examples that resolve those choices.

Writing a Synquid target under a guessed `insert_at` signature, or choosing exception/option/precondition behavior, would be a silent interface change. No contract was therefore supplied and **no synthesis invocation was made**. This is not a runtime limitation: it is a source-specification boundary.

## Test artifact

`test_generated.ml` uses only the OCaml standard library and opens `Generated`. It has an isolated valid-position oracle, illustrative boundary/property checks, and no calls to an invented generated API. Its negative control is intentionally wrong and fails when enabled:

```sh
./test_generated --negative-control
```

The negative control expects `[1; 2; 9]` after inserting `9` at index `1` into `[1; 2]`; the oracle yields `[1; 9; 2]`, so the assertion must fail. This validates the harness's equality assertion, **not** an unstated `Generated` interface.

## Required addendum before synthesis

Provide a solution-free authoritative declaration of the entrypoint/signature plus the complete valid- and invalid-index policy. With that information, the target can be specified with an exact sequence relation, preserving the original list's order and multiplicity rather than relying on only a length/set postcondition.
