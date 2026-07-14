# Published results (standing build)

Sanitized aggregates only. No raw harmful probe text.

| File | What |
|---|---|
| `refusal_suite_live.json` | Live suite **32/32** hard-refuse bypass (thinking **off**) |
| `refusal_probe_hybrid_l65_l30.json` | Standing recipe aggregate: bypass **32/32**, C1 speed |
| `serve_speed1_standing.json` | Serve knobs + C1 ≈ 30 tok/s @ 128k on 4× GB10 |

## Headline

| Metric | Result |
|---|---|
| Hard-refuse bypass | **32/32 (100%)** |
| Coherence | **6/6** |
| Garbled | **0** |
| C1 structured (count/list) | **~29.7–30.2 tok/s** |
| C1 essay (prose) | **~17.7 tok/s** (report separately) |

Probe protocol for apples-to-apples: `enable_thinking: false`, temperature 0.
