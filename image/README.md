# Serve image (self-contained bake)

## Preferred path (no bake)

```bash
bash scripts/pull_image.sh
# pulls: ghcr.io/drowzeys/vllm-node-tf5-glm52-b12x:speed1-c1-30-128k
# tags:  vllm-node-tf5-glm52-b12x:probe-modded
```

`oneshot.sh` does this for you.

## Rebuild from this repo only (if GHCR is unavailable)

Everything required for **patching** lives in this repository:

| In this repo | Role |
|---|---|
| `image/mods/glm52-sm12x-sparse/run.sh` | Sparse-MLA + DeepGEMM SM12x (tonyd2wild / CosmicRaisins lineage) |
| `image/mods/glm52-b12x-sparse/run.sh` | b12x for FULL cudagraph decode |
| `image/patches/fix-indexer-mtp-overhang.py` | MTP indexer fix (tonyd2wild) |
| `kernels/*.py` | CosmicRaisins pack + standing extras (`indexer.py`, `deepseek_mtp.py`) |
| `image/pins.env` | vLLM commit + image tags |
| `third_party/tonyd2wild/` | Full vendored tonyd recipe files + NOTICE |
| `third_party/CosmicRaisins-glm-5.2-gb10/` | LICENSE / NOTICE / ATTRIBUTION |

```bash
# Full base build + mods + patch (~35–90 min)
bash image/bake_image.sh

# If you already have vllm-node-tf5-glm52-b12x:probe:
bash image/bake_image.sh --mods-only
```

`bake_image.sh` will still **git clone** `eugr/spark-vllm-docker` once (build harness only — not our patches). All mods/patches/kernels are mounted from **this** repo.

### Pins (`image/pins.env`)

| Pin | Value |
|---|---|
| vLLM | `ab666069935c1f23e8ef56038b4659ac9e8f19f8` |
| Base tag | `vllm-node-tf5-glm52-b12x:probe` |
| Standing tag | `vllm-node-tf5-glm52-b12x:probe-modded` |
| GHCR | `…:speed1-c1-30-128k` |

### Bake traps (from tonyd2wild)

1. Always `docker commit` with  
   `--change 'ENTRYPOINT ["/opt/nvidia/nvidia_entrypoint.sh"]' --change 'CMD []'`  
2. Kernels must be at `/root/models/models15/glm-triton` inside the patch container (bake script does this).  
3. Use `docker exec` (with stdin if piping); without it, scripts can silently no-op.

## Layout

```text
image/
  bake_image.sh
  pins.env
  mods/glm52-sm12x-sparse/run.sh
  mods/glm52-b12x-sparse/run.sh
  patches/fix-indexer-mtp-overhang.py
third_party/tonyd2wild/     # source-of-truth copies + launch.sh
kernels/                    # bind-mounted at serve + used during bake
```
