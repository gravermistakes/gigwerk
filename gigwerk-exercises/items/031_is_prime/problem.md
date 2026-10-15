---
id: "031"
title: "Determine Whether a Given Integer Number Is Prime"
source_repository: "ocaml/ocaml.org"
source_commit: "7b4c04b90b5433050bcecb25772880bc48bae4d0"
source_path: "data/exercises/031_is_prime.md"
source_blob_sha: "74d9b145b17f3be5fee9868f1910165c78de420d"
solution_quarantine: "The single ## Solution section was removed before this artifact was inspected or authored."
---

# Determine Whether a Given Integer Number Is Prime

**Source metadata:** difficulty **intermediate**; tags **arithmetic**; source description: “Check if a given integer is a prime number.”

## Statement

Determine whether a given integer number is prime.

## Official examples

```ocaml
# not (is_prime 1);;
- : bool = true
# is_prime 7;;
- : bool = true
# not (is_prime 12);;
- : bool = true
```

## Extracted interface

```ocaml
is_prime : int -> bool
```

The REPL examples establish this interface and the three example outcomes above.

## Source-bound semantic note

The retained statement does **not** say how `0` or negative integers are classified. This artifact intentionally does not infer a signed-input policy from the quarantined section. The independent tests check exact truth values only on positive integers; they separately check that representative `int` edge inputs return a `bool` rather than raise. A backend contract claiming exact truth values for non-positive values needs an explicit policy before it can be called complete.

## Provenance and quarantine procedure

Fetched read-only through the GitHub API at the pinned commit named above. The source contained exactly one `## Solution` heading. The sanitizer removed that heading and all content through the next `##` heading (or EOF), before displaying or inspecting any remaining content. The resulting solution-free source text has SHA-256:

```text
0b7b0842ce972aef0cf9fa41766167b37f93e8f9816eb41bce544afac1e57001
```
