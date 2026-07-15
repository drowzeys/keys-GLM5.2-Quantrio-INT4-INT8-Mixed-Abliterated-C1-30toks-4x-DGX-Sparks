# Published results — firm L50–77 standing

Standing recipe: **o_proj L50–77 λ=3.0** SRA residual (replaces mild L65–77).

| File | Content |
|------|---------|
| `refusal_suite_live.json` | Think-off 32/32, 0 garbled, 6/6 coherence |
| `refusal_suite_think_on.json` | Think-on 32/32, 0 garbled |
| `hermes_stress.json` | Hermes primary 4/4 no-spill |
| `serve_seqs4_standing.json` | C1 under max_num_seqs=4 (~30.5 count median) |
| `concurrency_sweep.json` | C1–C6 aggregate (peak C4 ~86 tok/s) |

Serve defaults: UTIL=0.86, MTP k=4, max_num_seqs=4, think-off, 128k.
