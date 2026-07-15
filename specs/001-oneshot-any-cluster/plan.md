# Plan (implemented) — firm L50–77

Install-only repository surface:

- `scripts/oneshot.sh` orchestrates preflight → kernels → image → NCCL → weights → fanout → launch  
- `recipe/cluster.env.example` for any fleet (`SPEED=0` `MAX_NUM_SEQS=4`)  
- `recipe/DIRTY_SHARDS.json` lists **28** firm dirty shards (L50–77 o_proj)  
- `results/` holds 32/32 suite (think-off + think-on), Hermes stress, seqs=4 C1, concurrency sweep  
- No alternate install documentation  
- Mild late-only L65–77 is **replaced** by firm L50–77 on HF + GitHub  
