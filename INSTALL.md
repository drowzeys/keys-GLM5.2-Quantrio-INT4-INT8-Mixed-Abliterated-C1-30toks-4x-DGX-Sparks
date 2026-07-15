# Install — download and run (firm L50–77)

This file is the full install guide. The short version is in [README.md](README.md).

Standing recipe: **firm** residual ablit — `self_attn.o_proj` **L50–77**, λ=**3.0**, **28 dirty shards**  
(replaces prior mild late-only L65–77).

## 1. Clone

```bash
git clone https://github.com/drowzeys/keys-GLM5.2-Quantrio-INT4-INT8-Mixed-Abliterated-C1-30toks-4x-DGX-Sparks
cd keys-GLM5.2-Quantrio-INT4-INT8-Mixed-Abliterated-C1-30toks-4x-DGX-Sparks
```

## 2. Cluster config (required)

```bash
cp recipe/cluster.env.example recipe/cluster.env
```

Edit:

| Variable | Meaning |
|---|---|
| `NODES` | Four fabric IPs, **head first** |
| `SSH_USER` | SSH user on all nodes (passwordless key from head) |
| `SSH_KEY` | Path to private key |
| `NCCL_*` | RoCE HCA / interface (or run detect below) |

```bash
bash scripts/detect_fabric.sh --write
# merge NCCL_* lines from recipe/cluster.env.detected into cluster.env if needed
```

## 3. HF token (required)

1. Accept terms on [drowzeys/GLM-5.2-Int4-Int8Mix-Abliterated](https://huggingface.co/drowzeys/GLM-5.2-Int4-Int8Mix-Abliterated)  
2. `export HF_TOKEN=hf_...`

## 4. One command

```bash
bash scripts/oneshot.sh --all
```

Wait ~12–20+ minutes for weight load + cudagraph warmup, then:

```bash
curl -s http://HEAD:8210/v1/models
```

## Stages inside oneshot

| # | Action |
|---|---|
| 0 | Preflight (git/docker/ssh/disk/HF) |
| 1 | Kernels → `~/glm-triton` (all ranks) |
| 2 | Pull GHCR image (all ranks) |
| 3 | Stage NCCL 2.30.4 (all ranks) |
| 4 | Download **firm** ablit weights + verify **28** dirty shards + hub symlink |
| 5 | Fanout weights to workers + remote verify |
| 6 | Diagnose head |
| 7 | Launch **max_num_seqs=4** · TP=4 |
| + | Refusal suite (32/32 claim) |

## Install only (no launch)

```bash
export HF_TOKEN=hf_...
bash scripts/oneshot.sh --fanout
SPEED=0 MAX_NUM_SEQS=4 bash serve/launch-keyspark.sh   # when ready
bash serve/launch-keyspark.sh --stop                    # stop
```

## Standing serve knobs (published firm profile)

| Knob | Value |
|---|---|
| SPEED | **0** |
| MAX_NUM_SEQS | **4** |
| MAX_MODEL_LEN | 128000 |
| UTIL | 0.86 |
| KV_BYTES | 7008000000 |
| MTP_K | 4 |
| kv-cache-dtype | fp8_ds_mla |
| thinking | **off** |
| Port | 8210 |
| Hub path | `/cache/huggingface/hub/glm52-int4-int8mix` → **abliterated** tree |

### Ablit recipe (in weights)

| Item | Value |
|---|---|
| Modules | `self_attn.o_proj` only |
| Layers | **50–77** |
| λ | **3.0** |
| Dirty shards | **28** of 124 (see `recipe/DIRTY_SHARDS.json`) |
| Direction | SRA prefill rank-1 (`recipe/direction/`) |

## Failures (fix in order)

| Symptom | Fix |
|---|---|
| oneshot refuses NODES | Set `recipe/cluster.env` |
| HF download fails | Gate + `HF_TOKEN` |
| verify FAIL | Re-run oneshot; do not serve stock QuantTrio; need all **28** dirty shards |
| Partial refusals | Fanout on **every** rank; probe with thinking **off** |
| ~half tok/s | IB not in container / wrong NCCL ifname — re-check cluster.env |
| API timeout | Wait 20+ min; `docker logs -f vllm_qt200k` on head |

## Image rebuild (self-contained; only if GHCR pull fails)

```bash
bash image/bake_image.sh          # base vLLM + mods + indexer patch
bash scripts/fanout_image.sh      # after bake, send to workers
```

See `image/README.md` and `third_party/README.md`.

## Agents

See [AGENTS.md](AGENTS.md). Single allowed path: `bash scripts/oneshot.sh --all`.
