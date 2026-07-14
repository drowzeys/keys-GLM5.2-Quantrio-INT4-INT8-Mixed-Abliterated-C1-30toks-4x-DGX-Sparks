# Serve image

**Preferred:** pull the public image (oneshot does this):

```text
ghcr.io/drowzeys/vllm-node-tf5-glm52-b12x:speed1-c1-30-128k
→ local tag vllm-node-tf5-glm52-b12x:probe-modded
```

`mods/` and `patches/` document the bake lineage (tonyd2wild / CosmicRaisins).  
You do **not** need to rebuild if GHCR pull works.
