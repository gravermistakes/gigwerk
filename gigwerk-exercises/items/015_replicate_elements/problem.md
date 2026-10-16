# Provenance

- **Upstream repository:** `ocaml/ocaml.org`
- **Pinned commit:** `7b4c04b90b5433050bcecb25772880bc48bae4d0`
- **Source path:** `data/exercises/015_replicate_elements.md`
- **Retrieval:** GitHub Contents API, read-only. Exactly one `## Solution` section was removed before inspection.

---

---
title: Replicate the Elements of a List a Given Number of Times
slug: "15"
difficulty: intermediate
tags: [ "list" ]
description: "Write a function that replicates the elements of a list a given number of times."
---

## Statement

Replicate the elements of a list a given number of times.

```ocaml
# replicate ["a"; "b"; "c"] 3;;
- : string list = ["a"; "a"; "a"; "b"; "b"; "b"; "c"; "c"; "c"]
```
