# Independent test negative-control evidence

The independently authored OCaml test suite was compiled against an explicitly labelled, deliberately incorrect **test-only stub outside this deliverable directory**:

```ocaml
let pack (_ : 'a list) : 'a list list = []
```

The linked test process exited **2** (non-zero as required), with the expected semantic assertion:

```text
FAIL [NEGATIVE CONTROL: separated equal values are not coalesced]: semantic assertion failed
```

This red-phase result demonstrates that the suite rejects incorrect behavior. It is not a candidate implementation and does not establish a passing implementation.
