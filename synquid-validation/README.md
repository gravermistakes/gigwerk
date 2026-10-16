# Synquid → OCaml: persistent BST validation

## Result

**Successful for the tested contract.** Synquid derived recursive binary-search-tree insertion from a refinement contract with a complete implementation hole. A small syntax-only adapter converted the emitted expression to OCaml. The resulting function compiled as bytecode and native code and passed **308,280 assertions per test run**.

This is a real contract-to-program experiment, not an agent-written insertion algorithm passed off as generated output. No model calls were used. GigWerk itself was not modified.

## Contract and input boundary

Input: the upstream `test/current/BST-Insert.sq` benchmark, copied unchanged to `contracts/BST-Insert.sq`.

```text
data BST a where
  Empty :: BST a
  Node :: x:a -> l:BST {a | _v < x} -> r:BST {a | x < _v} -> BST a

insert :: x:a -> t:BST a -> {BST a | telems _v == telems t + [x]}
insert = ??
```

The complete fixture also supplies:

- A structural `size` termination measure.
- A `telems` measure describing the tree's element set.
- Comparison qualifiers used by the symbolic construction/checking machinery.

The contract requires an ordered BST containing exactly the old element set union the inserted key. **Duplicate keys have set semantics**, not multiset semantics. Nothing in the fixture supplies insertion branch bodies, a completed insertion helper, or concrete input/output training examples.

The source format is **Synquid `.sq`, not OCaml or Prolog**. It describes an algebraic data structure that maps directly to an OCaml variant. This experiment tests that mapping, not direct ingestion of arbitrary OCaml specifications.

## What Synquid actually emitted

The complete raw result is preserved in `evidence/synquid-BST-Insert.out`. Its generated function is:

```text
insert = \x . \t .
  match t with
    Empty -> Node x Empty Empty
    Node x7 x8 x9 ->
      if (x <= x7) && (x7 <= x)
        then t
        else
          if x7 <= x
            then Node x7 x8 (insert x x9)
            else Node x7 (insert x x8) x9
```

The branches, duplicate test, recursive calls and reconstruction came from Synquid. They were not supplied by the agent.

### Export discrepancy discovered by execution

The checked revision advertises `--out-file` / `--out-module` as Haskell export options. The CLI accepts them but never uses those fields in `main`/`runOnFile`; no requested Haskell file was written. The initial source survey's assumption that these flags implement a working export was incorrect for this revision.

**Actual stock output here is Synquid's expression on stdout—not Haskell or OCaml.** This finding is important when estimating integration work.

## OCaml result and adapter boundary

`ocaml/generated_bst.ml` contains:

```ocaml
type 'a bst = Empty | Node of 'a * 'a bst * 'a bst

let rec insert (x : int) (t : int bst) : int bst =
  match t with
  | Empty ->
    Node (x, Empty, Empty)
  | Node (x7, x8, x9) ->
    if ((x <= x7) && (x7 <= x)) then
      t
    else
      if (x7 <= x) then
        Node (x7, x8, (insert (x) (x9)))
      else
        Node (x7, (insert (x) (x8)), x9)
```

`tools/lower.py` parses the emitted expression into a small AST and renders OCaml. It does not substitute an algorithm, change conditions or choose branches. It changes lambda/function notation, layout matches, constructor arguments and parentheses. The adapter provides the corresponding OCaml type declaration and **specializes the key domain to OCaml `int`**.

It deliberately supports only this experimental fragment: two top-level arguments, a complete single-level BST match, `Empty`/`Node`, pure recursive calls, comparisons, Boolean connectives and conditionals. It rejects holes, unknown/unbound symbols, malformed constructors, partial matches and unsupported callables. It is **not a general Synquid-to-OCaml compiler**, a formal semantic-preservation proof, or a production capability sandbox.

The exported variant exposes raw constructors. Callers must provide a valid input BST, as the original contract requires; OCaml's ordinary type system does not retain the refinement invariant. A production interface would need an invariant-preserving boundary.

## Executed checks

| Check | Observed result |
|---|---|
| Contract-driven synthesis | Success; original run 1.677 seconds including PRoot overhead |
| Second synthesis run | Success; 1.569 seconds, byte-identical stdout |
| Supplied generated body rechecked by Synquid | Accepted against the same contract |
| Wrong body `insert = \x . \t . t` | Rejected by the refinement checker, exit 1 |
| Adapter tests | 11 passed; first recorded run failed because the adapter was absent |
| OCaml bytecode compilation | Success, OCaml 4.14.1 |
| OCaml native compilation | Success, OCaml 4.14.1 |
| OCaml property tests | 308,280 assertions passed per backend |
| Incorrect OCaml negative control | Compiled, then failed the exact set-union assertion |

The property tests include **2,950 independently generated valid BSTs**, **26,550 exhaustive insertion cases**, **20,000 deterministic randomized sequence steps**, integer extremes, duplicate insertions and ascending/descending chains of 500 keys. The generator does not use the synthesized insertion function to construct exhaustive input trees.

The independent oracle is OCaml `Set.Make(Int)`. Tests check strict ordering, exact key preservation, immutable input observations, size relative to the expected set and duplicate-key behavior. Finite tests are independent evidence, **not a proof for every possible OCaml tree**. The Synquid recheck uses the same symbolic checker, not an independent theorem prover. No full upstream Synquid suite was run.

## Runtime provenance

- Canonical source checkout: `9bceb4cc775e07ab279fff8c51fdd86ae0b2878c`.
- Runtime: the image linked by the upstream README, `yinengy/synquid`.
- Pinned image digest: `sha256:b2af75b010ddba20d4a99068bfabdf7e2d2f6539997185cad0a0b8d1625659f6`.
- Image source checkout: `b7f9d4ba801e576e0c34ed0b574cda620fe05443`; comparison found no differences between its `src/` directory and the canonical checkout's `src/` directory.
- Runtime CLI reports Synquid 0.4. The executable hashes, image manifest, help text, source hashes and logs are retained under `evidence/`.
- The image was retrieved with Skopeo, unpacked rootlessly with umoci and run through PRoot. **No Docker daemon or persistent service was started. PRoot here is a runtime compatibility tool, not a claimed security boundary.**

The upstream image is approximately 1.52 GB compressed. It is intentionally not included in the source/test ZIP. This was a pinned prebuilt runtime test, not a fresh Haskell source build.

## Reproduce

To compile and test the preserved generated output, without Synquid:

```bash
bash run-ocaml-tests.sh
```

Requires Python 3 and OCaml 4.14-compatible `ocamlc`/`ocamlopt`; no third-party Python packages are used.

To retrieve the exact runtime on an appropriate Linux AMD64 host:

```bash
mkdir -p runtime
skopeo copy \
  docker://yinengy/synquid@sha256:b2af75b010ddba20d4a99068bfabdf7e2d2f6539997185cad0a0b8d1625659f6 \
  oci:runtime/image:pinned
umoci unpack --rootless --image runtime/image:pinned runtime/bundle
SYNQUID_ROOTFS="$PWD/runtime/bundle/rootfs" bash run-synthesis.sh
```

The synthesis script runs with a 120-second external timeout, regenerates the OCaml artifact through the adapter and reruns the tests. It does not use the broken Haskell export flags.

## Assessment for GigWerk

**Yes: Synquid is a credible source of model-free, requirement-directed recursive functional code for this data-structure class.** This test is materially beyond the arithmetic prototype.

The remaining work is not inventing an insertion algorithm. It is a supported contract frontend, a proper typed OCaml backend, stable failure/budget handling and integration with GigWerk's booked actor and ledger. The observed export gap means a stock backend cannot be assumed.

No balanced-tree guarantee, arbitrary-code capability, general effect handling, Prolog contract frontend, native ARM64 build, JNI binding, APK, Android execution or complete GigWerk integration was tested or delivered. The OCaml source is portable source; the validation runtime and compiled host executables are not Android artifacts.

## Sources

- [Synquid repository and official image reference](https://github.com/nadia-polikarpova/synquid)
- [Exact upstream BST contract](https://github.com/nadia-polikarpova/synquid/blob/9bceb4cc775e07ab279fff8c51fdd86ae0b2878c/test/current/BST-Insert.sq)
- [CLI code exposing but not wiring export fields](https://github.com/nadia-polikarpova/synquid/blob/9bceb4cc775e07ab279fff8c51fdd86ae0b2878c/src/Synquid.hs)
- [Primary synthesis-course explanation](https://people.csail.mit.edu/asolar/SynthesisCourse/Lecture22.htm)
- [OCaml variant pattern semantics](https://ocaml.org/manual/patterns.html)
- [OCaml set oracle API](https://ocaml.org/docs/sets)

The supplied upstream contract/license are retained for attribution in `UPSTREAM_LICENSE`.
