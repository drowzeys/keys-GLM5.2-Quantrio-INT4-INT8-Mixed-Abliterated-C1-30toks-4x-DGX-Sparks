#!/usr/bin/env bash
# Stage NCCL 2.30.4 for LD_PRELOAD (tonyd2wild / CosmicRaisins recipe).
#   bash scripts/stage_nccl.sh
#   bash scripts/stage_nccl.sh --fanout
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/lib/common.sh"
init_cluster

DO_FANOUT=0
for a in "$@"; do
  case "$a" in
    --fanout) DO_FANOUT=1 ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) die "unknown arg: $a" ;;
  esac
done

NCCL_VER="${NCCL_VER:-2.30.4}"
DEST="${NCCL_DIR:-$WEIGHTS_DIR/hub/nccl-2.30.4}"
TMP="${TMPDIR:-/tmp}/nccl-stage-$$"

stage_local() {
  say "Stage NCCL $NCCL_VER → $DEST"
  if [ -f "$DEST/libnccl.so.2" ]; then
    ok "already present: $DEST/libnccl.so.2"
    return 0
  fi
  mkdir -p "$DEST" "$TMP"
  if ! command -v pip >/dev/null 2>&1 && ! command -v pip3 >/dev/null 2>&1; then
    die "pip required to download nvidia-nccl-cu13==$NCCL_VER"
  fi
  PIP=$(command -v pip3 || command -v pip)
  "$PIP" download "nvidia-nccl-cu13==$NCCL_VER" -d "$TMP" --no-deps -q \
    || die "pip download nvidia-nccl-cu13==$NCCL_VER failed"
  whl=$(ls "$TMP"/nvidia_nccl_cu13-*.whl 2>/dev/null | head -1)
  [ -n "$whl" ] || die "no nccl wheel in $TMP"
  (cd "$TMP" && unzip -qo "$whl" 'nvidia/nccl/lib/libnccl.so.2')
  cp -f "$TMP/nvidia/nccl/lib/libnccl.so.2" "$DEST/libnccl.so.2"
  chmod a+r "$DEST/libnccl.so.2"
  rm -rf "$TMP"
  ok "installed $DEST/libnccl.so.2"
}

stage_local

if [ "$DO_FANOUT" = "1" ]; then
  normalize_nodes
  if [ -z "${WORKERS:-}" ] && [ "${#NODES_ARR[@]}" -le 1 ]; then
    warn "no workers — skip NCCL fanout"
    exit 0
  fi
  say "Fanout NCCL to workers"
  for ip in ${WORKERS:-}; do
    echo "  → $ip"
    remote "$ip" "mkdir -p $DEST"
    rsync -a -e "$(ssh_cmd)" \
      "$DEST/libnccl.so.2" "$(node_user "$ip")@$ip:$DEST/libnccl.so.2" \
      || die "NCCL rsync failed → $ip"
    remote "$ip" "test -f $DEST/libnccl.so.2" || die "NCCL missing on $ip after rsync"
    ok "NCCL on $ip"
  done
fi

echo "OK — NCCL staged (LD_PRELOAD path inside container: /cache/huggingface/hub/nccl-2.30.4/libnccl.so.2)"
