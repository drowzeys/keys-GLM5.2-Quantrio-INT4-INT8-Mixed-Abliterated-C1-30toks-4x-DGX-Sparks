# Constitution — download-and-run ablit install

## I. One entrypoint

`bash scripts/oneshot.sh` is the only supported install path. No alternate graphs.

## II. Any 4× DGX Spark

Cluster knobs live in `recipe/cluster.env` (from example). No hardcoded lab IPs.

## III. Every rank identical

Kernels, image, NCCL, ablit weights, and hub symlink on **all four** nodes.

## IV. Ablit in weights

Published bypass requires gated abliterated HF tree + verify PASS. Not applied at launch.

## V. Published claims

- Refusal: **32/32** (thinking off) — `results/refusal_suite_live.json`
- Speed: C1 ≈ **30 tok/s** @ 128k SPEED=1 — `results/serve_speed1_standing.json`

## VI. Fail loud

Missing HF_TOKEN, verify FAIL, empty NODES, or SSH failure → non-zero exit with fix.

**Version**: 2.0.0 | **Ratified**: 2026-07-14
