# Third-party vendored sources

This repository is **self-contained** for standing install + image bake.
You do **not** need to visit other GitHub projects for mods, patches, or kernels.

| Directory | Upstream | What we vendor |
|---|---|---|
| `tonyd2wild/` | [tonyd2wild/GLM-5.2-QuantTrio-200K-4x-DGX-Spark](https://github.com/tonyd2wild/GLM-5.2-QuantTrio-200K-4x-DGX-Spark) | `mods/`, `patches/fix-indexer-mtp-overhang.py`, `launch.sh`, LICENSE, NOTICE |
| `CosmicRaisins-glm-5.2-gb10/` | [CosmicRaisins/glm-5.2-gb10](https://github.com/CosmicRaisins/glm-5.2-gb10) | LICENSE, NOTICE, ATTRIBUTION; **kernels live in repo-root `kernels/`** |

Canonical bake entrypoint: `bash image/bake_image.sh`  
(uses `image/mods` + `image/patches` + `kernels/`, which match `third_party/tonyd2wild/`).

Network is only required for:

1. Optional: public GHCR pull (`scripts/pull_image.sh`) — preferred  
2. Or: clone `eugr/spark-vllm-docker` + build vLLM at the pin in `image/pins.env`  
3. pip `b12x` during the b12x mod (bake time)
