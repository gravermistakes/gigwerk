# 021 — Insert an Element at a Given Position Into a List

## Provenance

- **Authoritative repository:** `ocaml/ocaml.org`
- **Pinned commit:** `7b4c04b90b5433050bcecb25772880bc48bae4d0`
- **Authoritative path:** `data/exercises/021_insert_element.md`
- **Blob SHA returned by GitHub API:** `f32f84b83e22f2b2b05571ce43d7b9d05b48a9c0`
- **Retrieval method:** read-only `gh api` GitHub Contents API request.

## Solution quarantine

The decoded source contained exactly one level-2 heading named `Solution`. Extraction retained only the bytes preceding that heading. No body from the quarantined section was read, retained, used, or reproduced.

## Authoritative non-solution source

```yaml
---
title: Insert an Element at a Given Position Into a List
slug: "21"
difficulty: beginner
tags: [ "list" ]
description: "Insert an element at a specified position (0-based index) within a list."
---
```

## Source-supported requirements

1. The operation inserts an element into a list.
2. Its position is specified by a **0-based index**.

## Specification boundary and ambiguity

The authoritative non-solution portion ends immediately after the front matter; it declares **no OCaml function identifier, type signature, argument order, official examples, valid-index domain, or behavior outside the list's positions**. Therefore this item cannot truthfully publish the requested exact OCaml interface or a fully semantic synthesis contract from the permitted source material.

In particular, this package does **not** silently choose among possible APIs such as `insert_at : 'a -> int -> 'a list -> 'a list` versus other argument orders, nor does it invent an exception, option, or clamping rule for out-of-range positions. `contract.sq` is intentionally absent: supplying one would require choosing an unstated interface and failure policy.

`test_generated.ml` contains a standard-library-only, isolated oracle for valid 0-based positions and a deliberate negative-control assertion. It opens `Generated`, but makes no call into an unstated candidate entrypoint. It is a harness/template, not evidence that a generated implementation meets this exercise.
