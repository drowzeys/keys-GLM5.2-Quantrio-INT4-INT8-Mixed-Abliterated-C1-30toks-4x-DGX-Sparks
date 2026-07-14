# Agents — this repo is download-and-run only

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
- Score refusal bypass with thinking **on**  
- Hand-roll hub paths (must be `hub/glm52-int4-int8mix` → abliterated)  
- Raise UTIL above **0.86** for this profile  

## Hard facts

1. Abliteration is **in the weights** (SRA o_proj L65–77 λ=3.0), not applied at launch.  
2. Standing claim: **32/32** bypass · see `results/refusal_suite_live.json`.  
3. Speed claim: C1 ≈ **30 tok/s** @ 128k · see `results/serve_speed1_standing.json`.  
4. Spec Kit constitution: `.specify/memory/constitution.md`.  

## After install

```bash
curl -s http://HEAD:8210/v1/models
bash scripts/diagnose_install.sh
bash serve/launch-keyspark.sh --stop   # if needed
```

Client must send `chat_template_kwargs: { enable_thinking: false }`.
