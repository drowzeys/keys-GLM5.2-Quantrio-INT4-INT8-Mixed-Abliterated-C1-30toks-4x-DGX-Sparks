# CosmicRaisins / glm-5.2-gb10 (kernels lineage)

Upstream: https://github.com/CosmicRaisins/glm-5.2-gb10 (Apache-2.0)

The sm_121 sparse-MLA Triton kernels used at serve time are **vendored in this repo** at:

```text
../../kernels/
```

Do not clone CosmicRaisins separately — `bash scripts/install_kernels.sh` copies from `kernels/` → `~/glm-triton`.

Extra files beyond the original CosmicRaisins 10 (GB10 / standing pack):

- `indexer.py` — instrumented indexer (includes MTP overhang handling)
- `deepseek_mtp.py` — QuantTrio MTP packed-modules mapping fix

See `KERNELS.upstream.txt` vs `KERNELS.vendored-here.txt`.
