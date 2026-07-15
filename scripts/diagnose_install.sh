#!/usr/bin/env bash
# diagnose_install.sh — why users see full OR partial (<100%) refusal bypass
#
# Run on EVERY TP rank. Exit 0 only if weights + hub look standing-ready.
# Does not require the server to be up (optional API check if BASE_URL set).
#
#   bash scripts/diagnose_install.sh
#   BASE_URL=http://10.100.10.4:8210/v1 bash scripts/diagnose_install.sh
#
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEIGHTS_DIR="${WEIGHTS_DIR:-/var/tmp/models}"
ABLIT_DIR="${ABLIT_DIR:-$WEIGHTS_DIR/glm52-int4-int8mix-abliterated}"
HUB="${HUB:-$WEIGHTS_DIR/hub/glm52-int4-int8mix}"
BASE_URL="${BASE_URL:-}"
HOST="$(hostname -s 2>/dev/null || hostname)"
FAILS=0
WARNS=0

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok()  { printf '  \033[32mOK\033[0m  %s\n' "$*"; }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAILS=$((FAILS+1)); }
warn(){ printf '  \033[33mWARN\033[0m %s\n' "$*"; WARNS=$((WARNS+1)); }

printf '\n\033[1;33mGLM-5.2 Quantrio ablit — install diagnosis on %s\033[0m\n' "$HOST"
printf 'Partial bypass is almost always install/serve path, not a weak HF upload.\n'

say "1) Ablit tree + dirty shards"
if [ -f "$ROOT/scripts/verify_ablit_weights.py" ]; then
  if python3 "$ROOT/scripts/verify_ablit_weights.py" --dir "$ABLIT_DIR" --hub "$HUB"; then
    ok "verify_ablit_weights.py PASS"
  else
    bad "verify_ablit_weights.py FAIL — re-run: bash scripts/oneshot_install_weights.sh"
  fi
else
  bad "missing $ROOT/scripts/verify_ablit_weights.py (clone full repo)"
fi

say "2) Hub path the launcher actually uses"
if [ -L "$HUB" ]; then
  ok "symlink $HUB -> $(readlink "$HUB") resolves $(readlink -f "$HUB" 2>/dev/null || true)"
elif [ -d "$HUB" ]; then
  bad "$HUB is a real directory (often stock). Need symlink to abliterated:"
  echo "       bash scripts/install_hub_symlink.sh"
else
  bad "missing $HUB — bash scripts/install_hub_symlink.sh"
fi
# Wrong hub name
WRONG="$WEIGHTS_DIR/hub/glm52-int4-int8mix-abliterated"
if [ -e "$WRONG" ]; then
  warn "extra hub name $WRONG exists — launcher does NOT use it (only glm52-int4-int8mix)"
fi
# Sibling stock
STOCK="$WEIGHTS_DIR/glm52-int4-int8mix"
if [ -d "$STOCK" ] && [ "$(readlink -f "$STOCK" 2>/dev/null)" != "$(readlink -f "$ABLIT_DIR" 2>/dev/null)" ]; then
  warn "sibling stock tree $STOCK — never pass this path to vllm serve"
fi

say "3) Serve image + kernels (firm max_num_seqs=4 recipe)"
if docker image inspect vllm-node-tf5-glm52-b12x:probe-modded >/dev/null 2>&1 \
  || docker image inspect ghcr.io/drowzeys/vllm-node-tf5-glm52-b12x:speed1-c1-30-128k >/dev/null 2>&1; then
  ok "standing image present (probe-modded or GHCR speed1-c1-30-128k)"
else
  bad "image missing — bash scripts/pull_image.sh"
fi
KDIR="${KERNELS_DIR:-$HOME/glm-triton}"
NKER=$(ls "$KDIR"/*.py 2>/dev/null | wc -l | tr -d ' ')
if [ "${NKER:-0}" -ge 8 ]; then
  ok "glm-triton kernels: $NKER py files in $KDIR"
else
  bad "$KDIR incomplete ($NKER files) — bash scripts/install_kernels.sh"
fi

say "3b) NCCL 2.30.4 preload (tonyd recipe)"
NCCL="${NCCL_DIR:-$WEIGHTS_DIR/hub/nccl-2.30.4/libnccl.so.2}"
if [ -f "$NCCL" ]; then
  ok "NCCL $NCCL"
else
  bad "missing $NCCL — bash scripts/stage_nccl.sh"
fi

say "4) Multi-node reminder"
echo "  Standing is TP=4. EVERY rank needs PASS on this script."
echo "  Mixed ranks (ablit on head, stock on worker) → flaky / partial bypass."
echo "  Fanout: NODES='head w1 w2 w3' bash scripts/oneshot.sh --fanout"
echo "  Config: recipe/cluster.env (from cluster.env.example)"

say "5) Probe protocol (false partial bypass)"
echo "  enable_thinking MUST be false for published 32/32 claim."
echo "  OpenAI body must include:"
cat <<'EOF'
    "chat_template_kwargs": {"enable_thinking": false}
  # or extra_body / client-specific thinking toggle OFF
EOF
echo "  Thinking ON → looks like refusals even with correct weights."

if [ -n "$BASE_URL" ]; then
  say "6) Live API ($BASE_URL)"
  code=$(curl -s -o /tmp/glm_models.json -w '%{http_code}' --max-time 5 "$BASE_URL/models" || echo 000)
  if [ "$code" = "200" ]; then
    ok "API /models HTTP 200"
    head -c 300 /tmp/glm_models.json; echo
    # thinking-off smoke (harmless prompt only)
    resp=$(curl -s --max-time 120 "$BASE_URL/chat/completions" \
      -H 'Content-Type: application/json' \
      -d '{
        "model": "glm-5.2",
        "temperature": 0,
        "max_tokens": 64,
        "messages": [{"role":"user","content":"Reply with exactly: ABLIT_OK"}],
        "chat_template_kwargs": {"enable_thinking": false}
      }' 2>/dev/null || true)
    if echo "$resp" | grep -q 'ABLIT_OK'; then
      ok "thinking-off generation works (ABLIT_OK)"
    else
      warn "generation smoke unclear — check: $resp"
    fi
  else
    bad "API not ready (HTTP $code) — start serve after weights PASS"
  fi
else
  say "6) Live API skipped (set BASE_URL=http://HEAD:8210/v1 to enable)"
fi

say "Result on $HOST"
if [ "$FAILS" -eq 0 ]; then
  printf '\033[1;32mPASS diagnosis — weights/hub look ready on this host\033[0m\n'
  [ "$WARNS" -gt 0 ] && printf '  (%s warning(s) — read above)\n' "$WARNS"
  echo "If clients still see partial refusals: INSTALL.md (thinking off + fanout)"
  exit 0
fi
printf '\033[1;31mFAIL diagnosis — %s issue(s) on this host\033[0m\n' "$FAILS"
echo "Fix with: bash scripts/oneshot_install_weights.sh"
echo "Docs: INSTALL.md"
exit 1
