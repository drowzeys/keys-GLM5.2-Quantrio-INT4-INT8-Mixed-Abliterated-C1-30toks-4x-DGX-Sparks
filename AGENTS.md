# Agents — this repo is download-and-run only (firm L50–77)

## Do this

```bash
cp recipe/cluster.env.example recipe/cluster.env
# edit NODES (head first) + SSH_USER
export HF_TOKEN=...
bash scripts/oneshot.sh --all
```

## Do not

- Invent alternate install graphs  
- Download QuantTrio **stock** and serve it as ablit  
- Skip fanout / install only on head  
- Score refusal bypass with thinking **on** for the published claim path  
- Hand-roll hub paths (must be `hub/glm52-int4-int8mix` → abliterated)  
- Raise UTIL above **0.86** for this profile  
- Install the old **mild L65–77** tree and call it firm (verify expects **28** dirty shards)

## Hard facts

1. Abliteration is **in the weights** (SRA o_proj **L50–77** λ=3.0), not applied at launch.  
2. Standing claim: **32/32** bypass think-off (and think-on) · see `results/refusal_suite_live.json`.  
3. Speed claim: C1 ≈ **30.5 tok/s** @ 128k with **max_num_seqs=4** · see `results/serve_seqs4_standing.json`.  
4. Spec Kit constitution: `.specify/memory/constitution.md`.  
5. **Self-contained:** kernels, tonyd2wild mods/patches, and bake script are **in this repo**  
   (`kernels/`, `image/`, `third_party/`). Do **not** send users to other GitHubs for patches.  
   Prefer GHCR pull; if rebuild needed → `bash image/bake_image.sh`.  

## After install

```bash
curl -s http://HEAD:8210/v1/models
bash scripts/diagnose_install.sh
bash serve/launch-keyspark.sh --stop   # if needed
```

Client must send `chat_template_kwargs: { enable_thinking: false }` for latency + agent use.
