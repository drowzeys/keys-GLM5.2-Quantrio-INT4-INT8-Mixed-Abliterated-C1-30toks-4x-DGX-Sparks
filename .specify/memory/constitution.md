# Constitution — download-and-run firm ablit install

## I. One entrypoint

`bash scripts/oneshot.sh` is the only supported install path. No alternate graphs.

## II. Any 4× DGX Spark

Cluster knobs live in `recipe/cluster.env` (from example). No hardcoded lab IPs.

## III. Every rank identical

Kernels, image, NCCL, ablit weights, and hub symlink on **all four** nodes.

## IV. Ablit in weights (firm L50–77)

Published bypass requires gated **firm** abliterated HF tree + verify PASS on **28 dirty shards**
(`self_attn.o_proj` layers **50–77**, λ=3.0). Not applied at launch. Replaces mild L65–77.

## V. Published claims

- Refusal: **32/32** think-off (and think-on) — `results/refusal_suite_live.json` / `refusal_suite_think_on.json`
- Speed: C1 ≈ **30.5 tok/s** @ 128k **max_num_seqs=4** — `results/serve_seqs4_standing.json`
- Hermes primary no-spill: **4/4** — `results/hermes_stress.json`
- Concurrent: C4 aggregate ~**86 tok/s** — `results/concurrency_sweep.json`

## VI. Fail loud

Missing HF_TOKEN, verify FAIL, empty NODES, or SSH failure → non-zero exit with fix.

**Version**: 3.0.0 | **Ratified**: 2026-07-15 | **Recipe**: firm L50–77 λ=3.0
