# GLM-5.2 Quantrio Abliterated · 4× DGX Spark

**Download and run.** One-shot install for any 4-node DGX Spark (GB10) cluster.

| | |
|---|---|
| **What** | Abliterated QuantTrio GLM-5.2 Int4/Int8 Mix · SPEED=1 · C1 ≈ **30 tok/s** @ 128k |
| **Refusal bypass** | **32/32 (100%)** with thinking **off** · [results/](results/) |
| **Image** | `ghcr.io/drowzeys/vllm-node-tf5-glm52-b12x:speed1-c1-30-128k` |
| **Weights** | [drowzeys/GLM-5.2-Int4-Int8Mix-Abliterated](https://huggingface.co/drowzeys/GLM-5.2-Int4-Int8Mix-Abliterated) (gated HF) |
| **API** | `http://HEAD:8210/v1` · model id `glm-5.2` |

> Hugging Face is **weights only**. This GitHub repo is the **install**.  
> Downloading HF files by hand is **not** a complete install.

---

## One-shot (humans + agents)

```bash
git clone https://github.com/drowzeys/keys-GLM5.2-Quantrio-INT4-INT8-Mixed-Abliterated-C1-30toks-4x-DGX-Sparks
cd keys-GLM5.2-Quantrio-INT4-INT8-Mixed-Abliterated-C1-30toks-4x-DGX-Sparks

cp recipe/cluster.env.example recipe/cluster.env
# REQUIRED: set NODES="HEAD W1 W2 W3" and SSH_USER=...
# Optional fabric helper:  bash scripts/detect_fabric.sh --write

export HF_TOKEN=hf_...   # accept gated HF model first
bash scripts/oneshot.sh --all
```

That single command:

1. Preflight (tools, disk, SSH to workers)  
2. Install sparse-MLA kernels on every rank  
3. Pull the public vLLM image on every rank  
4. Stage NCCL 2.30.4 on every rank  
5. Download **abliterated** weights + hub symlink + verify  
6. Fanout everything to all TP ranks  
7. Launch SPEED=1 serve  
8. Run refusal suite  

**Agents:** do **not** invent alternate paths. Run `bash scripts/oneshot.sh --all` after `recipe/cluster.env` is set. See [AGENTS.md](AGENTS.md).

Stop: `bash serve/launch-keyspark.sh --stop`

---

## Prerequisites

- **4×** NVIDIA DGX Spark (GB10), RoCE fabric between nodes  
- **≥420 GiB free** per node  
- Passwordless **SSH** from head → workers  
- Docker with GPU + `/dev/infiniband`  
- Gated HF access + `HF_TOKEN`  

---

## Published results

Standing build (thinking **off**):

| Metric | Value |
|---|---|
| Hard-refuse bypass | **32/32 (100%)** |
| Coherence | **6/6** |
| C1 count/list | **~29.7–30.2 tok/s** |
| Context | **128k** · MTP k=4 · `fp8_ds_mla` |

Raw JSON: [results/](results/) · suite: `results/refusal_suite_live.json` · speed: `results/serve_speed1_standing.json`

---

## Client (thinking OFF for bypass)

```yaml
model:
  default: glm-5.2
  base_url: http://HEAD:8210/v1
  extra_body:
    temperature: 0.0
    chat_template_kwargs: { enable_thinking: false, thinking: false }
```

---

## What is in this repo

```text
scripts/oneshot.sh          ← only entrypoint you need
recipe/cluster.env.example  ← your 4 node IPs + fabric
serve/launch-keyspark.sh    ← SPEED=1 TP=4 launcher
kernels/                    ← CosmicRaisins / tonyd sparse-MLA
image/ · patches/           ← image bake lineage (public GHCR already baked)
recipe/                     ← ablit meta, dirty shards, direction provenance
results/                    ← 32/32 suite + C1≈30 benchmarks
specs/ · .specify/          ← Spec Kit install constitution
```

Stock quant credit: [QuantTrio/GLM-5.2-Int4-Int8Mix](https://huggingface.co/QuantTrio/GLM-5.2-Int4-Int8Mix).  
Runtime lineage: [tonyd2wild QuantTrio-200K](https://github.com/tonyd2wild/GLM-5.2-QuantTrio-200K-4x-DGX-Spark) + CosmicRaisins. See [NOTICE](NOTICE).

## Responsible use

Weights are gated. Research / your own deployments only. Accept the HF card terms before download.
