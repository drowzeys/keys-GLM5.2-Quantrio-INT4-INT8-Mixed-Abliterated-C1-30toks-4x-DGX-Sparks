# Spec: Download-and-run oneshot (any 4× DGX Spark)

**Status**: Implemented (repo is install-only)

## Goal

A user or agent clones this repo, sets `recipe/cluster.env` + `HF_TOKEN`, runs
`bash scripts/oneshot.sh --all`, and gets standing ablit serve with published
**32/32** bypass and C1≈30 SPEED=1 behavior.

## Acceptance

1. One entrypoint only  
2. All ranks get kernels, image, NCCL, ablit weights  
3. Verify PASS before launch success  
4. Results published under `results/`  

## Non-goals

Rebuild-from-stock Path B docs, Hermes ops, forum narrative, intermediate ablit ladders.
