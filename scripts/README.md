# Scripts

**Start here:** `bash scripts/oneshot.sh --all`

| Script | Role |
|---|---|
| `oneshot.sh` | Master download-and-run |
| `preflight.sh` | Tools / disk / SSH / HF |
| `detect_fabric.sh` | RoCE HCA + ifname |
| `install_kernels.sh` | kernels → `~/glm-triton` |
| `pull_image.sh` | GHCR image |
| `stage_nccl.sh` | NCCL 2.30.4 |
| `oneshot_install_weights.sh` | HF ablit + verify + hub |
| `fanout_*.sh` | Multi-rank fanout |
| `diagnose_install.sh` | Per-host health |
| `verify_ablit_weights.py` | Dirty-shard verify |
| `refusal_suite.py` | 32/32 suite |
| `lib/common.sh` | cluster.env loader |
