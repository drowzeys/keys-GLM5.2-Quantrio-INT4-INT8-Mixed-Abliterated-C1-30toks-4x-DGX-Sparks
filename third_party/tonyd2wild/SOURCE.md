# Vendored from tonyd2wild/GLM-5.2-QuantTrio-200K-4x-DGX-Spark

Upstream: https://github.com/tonyd2wild/GLM-5.2-QuantTrio-200K-4x-DGX-Spark
Apache-2.0. See LICENSE and NOTICE in this directory.

## Files vendored here (used by image bake)

| Path | Role |
|---|---|
| `mods/glm52-sm12x-sparse/run.sh` | Install sparse-MLA kernels + DeepGEMM SM12x bypass into vLLM image |
| `mods/glm52-b12x-sparse/run.sh` | Install b12x for FULL cudagraph-safe sparse decode |
| `patches/fix-indexer-mtp-overhang.py` | Fix DSA indexer buffer under MTP (required for max-num-seqs ≥ 3) |
| `launch.sh` | Reference multi-node launcher (CosmicRaisins lineage) |

## Pins used for the standing ablit image

| Pin | Value |
|---|---|
| vLLM ref | `ab666069935c1f23e8ef56038b4659ac9e8f19f8` |
| Base harness | eugr/spark-vllm-docker (`./build-and-copy.sh --tf5`) |
| Base tag before mods | `vllm-node-tf5-glm52-b12x:probe` |
| After mods+patch | `vllm-node-tf5-glm52-b12x:probe-modded` |
| Public GHCR | `ghcr.io/drowzeys/vllm-node-tf5-glm52-b12x:speed1-c1-30-128k` |

Canonical bake: `bash image/bake_image.sh` (uses the copies under `image/mods` and `image/patches`, which match these files).
