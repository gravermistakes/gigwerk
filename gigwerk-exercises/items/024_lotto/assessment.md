
### Observed negative-control result

Fresh compilation succeeded with OCaml 4.14.1, and execution exited **2** with:

```text
Fatal error: exception Failure("official example parameters: output contains duplicate values")
```

This is the expected semantic rejection of the deliberately duplicate-producing negative control.
