# GLM-5.2 Quantrio Abliterated · 4× DGX Spark

**Download and run.** One-shot install for any 4-node DGX Spark (GB10) cluster.

| | |
|---|---|
| **What** | **Firm** abliterated QuantTrio GLM-5.2 Int4/Int8 Mix · **max_num_seqs=4** · C1 ≈ **30.5 tok/s** @ 128k |
| **Refusal bypass** | **32/32 (100%)** think-off **and** think-on · [results/](results/) |
| **Recipe** | `self_attn.o_proj` **L50–77** · λ=**3.0** · SRA prefill · **28 dirty shards** (replaces mild L65–77) |
| **Image** | `ghcr.io/drowzeys/vllm-node-tf5-glm52-b12x:speed1-c1-30-128k` (or `vllm-node-tf5-glm52-b12x:probe-modded`) |
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

export HF_TOKEN=hf_...   # accept gated HF model first
bash scripts/oneshot.sh --all
```

That single command:

1. Preflight (tools, disk, SSH to workers)  
2. Install sparse-MLA kernels on every rank  
3. Pull the public vLLM image on every rank  
4. Stage NCCL 2.30.4 on every rank  
5. Download **firm abliterated** weights + hub symlink + verify (**28** dirty shards)  
6. Fanout everything to all TP ranks  
7. Launch serve (`max_num_seqs=4` default for concurrent chat)  
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

## Standing recipe (firm — replaces mild)

| Item | Value |
|---|---|
| Modules | `self_attn.o_proj` only |
| Layers | **50–77** (was mild **65–77**) |
| λ | **3.0** |
| Edits | **28** o_proj modules |
| Dirty shards | **28** of **124** |
| Mean Δrel | ~0.040 |
| MTP / `eh_proj` | stock |
| Direction | SRA prefill rank-1 (`recipe/direction/`) |

### Published results (thinking **off**)

| Metric | Value |
|---|---|
| Hard-refuse bypass | **32/32 (100%)** |
| Think-on bypass | **32/32 (100%)** |
| Coherence | **6/6** |
| Garble | **0** |
| Hermes primary spill | **4/4 PASS** |
| C1 count (seqs=4) | **~30.5 tok/s** median (max ~31.2) |
| C4 aggregate | **~86 tok/s** |
| Context | **128k** · MTP k=4 · `fp8_ds_mla` |

Raw JSON: [results/](results/)

---

## Client (thinking OFF for speed + agent use)

```yaml
model:
  default: glm-5.2
  base_url: http://HEAD:8210/v1
  extra_body:
    temperature: 0.0
    chat_template_kwargs:
      thinking: false
      enable_thinking: false
```

---

## Credits

- **QuantTrio** — base Int4/Int8 Mix weights  
- **CosmicRaisins / Zatz / TonyD2Wild / back199640** — GB10 sparse-MLA serve recipe lineage  
- **Keys / drowzeys** — SRA residual abliteration + firm L50–77 standing  

## License

MIT for this packaging/scripts. Upstream GLM / QuantTrio licenses apply to weights.
