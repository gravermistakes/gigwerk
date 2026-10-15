# Verification record plan

1. Compile `negative_control_stub.ml` as module `Generated` and compile `test_generated.ml` against it. The executable must fail at an expected semantic assertion (the first official example), proving the test checks behavior rather than merely compiling.
2. Parse `interface.json` and `assessment.json` as JSON.
3. Confirm `contract.sq` contains `last_two = ??` and no manually authored target body.
4. A backend must mechanically lower a future Synquid candidate into `Generated.last_two` and rerun `test_generated.ml` before any fulfillment claim. A Synquid candidate alone is insufficient.
