# Spec: Download-and-run oneshot (any 4× DGX Spark)

**Status**: Implemented (repo is install-only)  
**Standing recipe**: firm o_proj **L50–77** λ=3.0 (28 dirty shards)

## Goal

A user or agent clones this repo, sets `recipe/cluster.env` + `HF_TOKEN`, runs
`bash scripts/oneshot.sh --all`, and gets **firm** ablit serve with published
**32/32** bypass (think-off) and C1≈**30.5** @ **max_num_seqs=4**.

## Acceptance

1. One entrypoint only  
2. All ranks get kernels, image, NCCL, firm ablit weights  
3. Verify PASS on **28** dirty shards before launch success  
4. Results published under `results/` for firm standing  

## Non-goals

Rebuild-from-stock Path B as primary install, Hermes ops beyond published stress JSON,
forum narrative, intermediate ablit ladders (mild L65–77 is retired).
