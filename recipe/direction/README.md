# Refusal direction (SRA prefill, rank-1 r=8)

Used by residual write projection for **firm** ablit (`self_attn.o_proj` **L50–77**, λ=3.0).

**You do not need this file for Path A.** One-shot installs pre-abliterated HF weights.

Path B (rebuild from QuantTrio stock):

```bash
python3 project_residual.py --fresh \
  --direction recipe/direction/refusal_direction_sra_prefill.pt \
  --modules self_attn.o_proj \
  --min-layer 50 --max-layer 77 --lambda-attn 3.0
```

Then verify against `recipe/DIRTY_SHARDS.json` (28 dirty shards).
