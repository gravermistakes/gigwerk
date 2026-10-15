# Local synthesis validation evidence

These are **research demos**, not a GigWerk implementation or proof that arbitrary software contracts can be synthesized.

## cvc5: formal constraints to functions

Pinned host package: Ubuntu `cvc5=1.1.2-1build1` (solver 1.1.2). Compiler/build details are in `cvc5-version.txt`; the executable SHA-256 is in `cvc5-binary.sha256`. This was not a build of the current upstream revision.

Input: upstream cvc5 `examples/api/smtlib/sygus-fun.sy`, copied as `sygus-fun.sy`. It describes maximum/minimum by logical constraints, not input/output examples or an implementation body.

Executed from the evidence directory:

```bash
cvc5 --lang=sygus2 --seed=0 --tlimit=10000 sygus-fun.sy > sygus-fun.out
cvc5 --lang=sygus2 --seed=0 --tlimit=10000 sygus-fun.sy > sygus-fun-replay.out
cmp sygus-fun.out sygus-fun-replay.out
cvc5 --seed=0 --tlimit=10000 sygus-fun-verify.smt2 > sygus-fun-verify.out
```

Each solver invocation additionally had a 20-second host `timeout`. Both synthesis invocations exited successfully and returned byte-identical definitions. The verification input fixes those definitions and asks for any integer input violating the original constraints; the result was `unsat`.

This is **same-solver semantic replay**, not an independent certificate checker. It does not validate a generated OCaml backend, recursion, stateful software, Android, or cross-platform deterministic output. The numeric example proves that the existing solver performs actual specification-directed construction; it is not proposed as the final actor capability.

## Metagol: relational construction and recursion

Upstream: https://github.com/metagol/metagol

Pinned checkout: `7b617992d30d3cee37a6f4bb8667f717a46cc6a3`. Host SWI-Prolog: 9.0.4. The included repository source has its BSD-3-Clause license.

Executed:

```bash
cd metagol/examples
timeout 20s swipl -q -s grandparent.pl -g halt
timeout 20s swipl -q -s mutual-recursion.pl -g halt
```

Outputs are retained as `metagol-grandparent.out` and `metagol-mutual-recursion.out`. The first constructed three clauses using an invented helper combining mother/father relations. The second constructed mutually recursive even/odd-like clauses from the provided predecessor facts.

Both produced actual programs and exited successfully. Their positive/negative requirements and metarules are in the supplied fixtures. This demonstrates **example-and-rule-relative program construction**, not general contract proof. Metagol is explicitly superseded by Popper upstream; successful demos do not imply current maintenance or suitability as GigWerk's final synthesis foundation.

## Product changes

None. GigWerk source and HSWIP were not changed by these validations. No model/API generation call was used. Synquid, SuSLik, Popper and Myth were inspected but not locally built or executed.
