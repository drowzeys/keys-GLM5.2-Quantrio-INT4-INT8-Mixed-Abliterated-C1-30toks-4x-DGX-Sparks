# Sparse-MLA kernels (vendored)

**Do not clone CosmicRaisins separately.** These files are the complete standing pack.

```bash
bash scripts/install_kernels.sh   # → ~/glm-triton
```

`oneshot.sh` does this on every rank. `serve/launch-keyspark.sh` bind-mounts them into the container.

| Source | Files |
|---|---|
| CosmicRaisins glm-5.2-gb10 | 10 Triton / sm12x sparse-MLA modules (see `MANIFEST.txt`) |
| Standing extras | `indexer.py`, `deepseek_mtp.py` |

Attribution: `third_party/CosmicRaisins-glm-5.2-gb10/`.  
Also used during image bake: `image/bake_image.sh` mounts this directory at the path the tonyd mods expect.
