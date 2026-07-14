# Plan (implemented)

Install-only repository surface:

- `scripts/oneshot.sh` orchestrates preflight → kernels → image → NCCL → weights → fanout → launch  
- `recipe/cluster.env.example` for any fleet  
- `results/` holds 32/32 suite + SPEED=1 benchmarks only  
- No alternate install documentation  
