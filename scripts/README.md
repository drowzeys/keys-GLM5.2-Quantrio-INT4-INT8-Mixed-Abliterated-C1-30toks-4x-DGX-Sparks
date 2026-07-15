# Scripts

| Script | Role |
|---|---|
| `oneshot.sh` | Master install (only supported path) |
| `oneshot_install_weights.sh` | HF firm ablit + verify + hub |
| `verify_ablit_weights.py` | Dirty-shard verify (**28** firm shards) |
| `fanout_ablit.sh` | Weights → workers |
| `fanout_image.sh` / `fanout_kernels.sh` | Image / kernels → workers |
| `install_kernels.sh` / `pull_image.sh` / `stage_nccl.sh` | Per-host stages |
| `detect_fabric.sh` | RoCE knobs |
| `diagnose_install.sh` | Post-install health |
| `refusal_suite.py` | Live refusal probe |
| `preflight.sh` | Tools / disk / SSH |

Defaults for launch: `SPEED=0` `MAX_NUM_SEQS=4` `UTIL=0.86` `MTP_K=4` `MAX_MODEL_LEN=128000`.
