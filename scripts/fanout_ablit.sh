#!/usr/bin/env bash
# Fanout abliterated weights to worker nodes + install launcher hub symlink.
#
#   NODES="head w1 w2 w3" bash scripts/fanout_ablit.sh
#   WORKERS="w1 w2 w3" bash scripts/fanout_ablit.sh
#   FANOUT_MODE=full|dirty
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/lib/common.sh"
init_cluster

SRC_A="${ABLIT_DIR}"
BASE="${STOCK_DIR:-$WEIGHTS_DIR/glm52-int4-int8mix}"
FANOUT_MODE="${FANOUT_MODE:-full}"   # full | dirty
LOG="${LOG:-/tmp/fanout_ablit.log}"
DIRTY_LIST="${DIRTY_LIST:-$ROOT/recipe/DIRTY_SHARDS.txt}"

normalize_nodes
if [ -z "${WORKERS:-}" ]; then
  die "WORKERS empty — set NODES=\"head w1 w2 w3\" or WORKERS=\"w1 w2 w3\""
fi

exec > >(tee -a "$LOG") 2>&1
echo "==== FANOUT START $(date -Is) mode=$FANOUT_MODE workers=$WORKERS ===="

[ -f "$SRC_A/config.json" ] || die "missing $SRC_A/config.json"
[ -f "$DIRTY_LIST" ] || die "missing dirty list $DIRTY_LIST"

bash "$ROOT/scripts/install_hub_symlink.sh"

for h in $WORKERS; do
  echo "==== worker $h $(date -Is) ===="
  remote "$h" "mkdir -p $WEIGHTS_DIR/hub $SRC_A"

  if [ "$FANOUT_MODE" = "full" ]; then
    echo "[$h] rsync full ablit tree..."
    rsync -aH --info=stats2 --partial \
      -e "ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
      "$SRC_A/" "$(node_user "$h")@$h:$SRC_A/"
  else
    if ! remote "$h" "test -f $BASE/config.json"; then
      echo "[$h] stock missing at $BASE — full rsync of ablit"
      rsync -aH --partial \
        -e "ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
        "$SRC_A/" "$(node_user "$h")@$h:$SRC_A/"
    else
      remote "$h" "bash -s" <<REMOTE
set -euo pipefail
BASE="$BASE"; ABL="$SRC_A"
if [ ! -f "\$ABL/config.json" ]; then
  echo "hardlink-clone stock -> ablit"
  rm -rf "\$ABL"
  cp -al "\$BASE" "\$ABL"
fi
REMOTE
      echo "[$h] rsync dirty shards + meta..."
      while read -r f; do
        [ -z "$f" ] && continue
        [ -f "$SRC_A/$f" ] || die "missing local $f"
        rsync -a --partial \
          -e "ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
          "$SRC_A/$f" "$(node_user "$h")@$h:$SRC_A/$f"
      done < "$DIRTY_LIST"
      for f in ABLIT_META.json config.json model.safetensors.index.json \
               tokenizer.json tokenizer_config.json generation_config.json \
               chat_template.jinja chat_template_original.jinja; do
        [ -f "$SRC_A/$f" ] && rsync -a \
          -e "ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
          "$SRC_A/$f" "$(node_user "$h")@$h:$SRC_A/$f" || true
      done
    fi
  fi

  remote "$h" "mkdir -p $WEIGHTS_DIR/hub && ln -sfn ../glm52-int4-int8mix-abliterated $WEIGHTS_DIR/hub/glm52-int4-int8mix && ls -la $WEIGHTS_DIR/hub/glm52-int4-int8mix"

  key_args=(); [ -f "$SSH_KEY" ] && key_args=(-i "$SSH_KEY")
  scp -q "${key_args[@]}" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$ROOT/recipe/DIRTY_SHARDS.json" "$ROOT/recipe/DIRTY_SHARDS.txt" \
    "$ROOT/scripts/verify_ablit_weights.py" \
    "$(node_user "$h")@$h:/tmp/"
  remote "$h" "python3 /tmp/verify_ablit_weights.py --dir $SRC_A --hub $WEIGHTS_DIR/hub/glm52-int4-int8mix --recipe /tmp/DIRTY_SHARDS.json" \
    || die "verify failed on $h"

  remote "$h" "bash -s" <<REMOTE
set -euo pipefail
BASE="$BASE"; ABL="$SRC_A"; LIST=/tmp/DIRTY_SHARDS.txt
if [ -f "\$BASE/config.json" ] && [ -f "\$LIST" ]; then
  bad=0
  while read -r f; do
    [ -z "\$f" ] && continue
    ib=\$(stat -c %i "\$BASE/\$f" 2>/dev/null || echo 0)
    ia=\$(stat -c %i "\$ABL/\$f" 2>/dev/null || echo 0)
    if [ "\$ia" = "\$ib" ] && [ "\$ia" != 0 ]; then
      echo "HARDLINKED_TO_STOCK \$f"
      bad=\$((bad+1))
    fi
  done < "\$LIST"
  echo "hardlink_bad=\$bad (must be 0)"
  [ "\$bad" = 0 ]
else
  echo "skip hardlink check (no stock tree on worker)"
fi
REMOTE

  echo "[$h] OK"
done

echo "FANOUT_COMPLETE $(date -Is)"
touch /tmp/FANOUT_READY
