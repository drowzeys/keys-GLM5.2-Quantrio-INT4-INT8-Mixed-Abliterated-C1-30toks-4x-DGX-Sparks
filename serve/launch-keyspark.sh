#!/usr/bin/env bash
#
# launch-keyspark.sh — Quantrio GLM-5.2 Int4-Int8Mix Abliterated on 4× GB10.
#
# Lineage: CosmicRaisins launch.sh → tonyd2wild QuantTrio-200K → this SPEED=1 pack.
# Cluster-agnostic: source recipe/cluster.env or env vars (NODES, SSH_*, NCCL_*).
#
#   cp recipe/cluster.env.example recipe/cluster.env   # edit once
#   ./launch-keyspark.sh
#   ./launch-keyspark.sh --dry-run
#   ./launch-keyspark.sh --stop
#
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/lib/common.sh"
init_cluster

# Fail if NODES still empty
if [ "${#NODES_ARR[@]}" -eq 0 ]; then
  cat >&2 <<EOF
ERROR: NODES is empty.

Set your 4 fabric IPs (head first), e.g.:

  cp $ROOT/recipe/cluster.env.example $ROOT/recipe/cluster.env
  # edit NODES=... SSH_USER=... NCCL_* ...
  bash $ROOT/scripts/detect_fabric.sh --write   # optional fabric helper

  # or one-liner:
  NODES="10.x.x.1 10.x.x.2 10.x.x.3 10.x.x.4" SSH_USER=\$USER \\
    bash $0
EOF
  exit 1
fi

# Prefer GHCR public image if local tag missing
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  if docker image inspect "$GHCR_IMAGE" >/dev/null 2>&1; then
    IMAGE="$GHCR_IMAGE"
  fi
fi

# Fail early if kernels missing
if [ ! -f "$KERNELS_DIR/sparse_mla_kernels.py" ]; then
  echo "ERROR: kernels not found in $KERNELS_DIR" >&2
  echo "  Run: bash $ROOT/scripts/install_kernels.sh" >&2
  exit 1
fi

# Standing SPEED=1 → max_num_seqs
MAX_NUM_SEQS="${MAX_NUM_SEQS:-${SPEED:+1}}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-1}"
if [ "${SPEED:-1}" = "1" ] && [ -z "${MAX_NUM_SEQS_SET:-}" ]; then
  MAX_NUM_SEQS="${MAX_NUM_SEQS:-1}"
fi

# Fabric must be set
if [ -z "${NCCL_IB_HCA:-}" ] || [ -z "${NCCL_SOCKET_IFNAME:-}" ]; then
  detect_fabric_into_env
fi
if [ -z "${NCCL_IB_HCA:-}" ] || [ -z "${NCCL_SOCKET_IFNAME:-}" ]; then
  die "NCCL_IB_HCA / NCCL_SOCKET_IFNAME unset — run: bash $ROOT/scripts/detect_fabric.sh --write"
fi
GLOO_SOCKET_IFNAME="${GLOO_SOCKET_IFNAME:-$NCCL_SOCKET_IFNAME}"

# Soft warn above the 0.86 GLM-5.2 exception (house hard cap is 0.85 elsewhere).
awk -v u="$UTIL" 'BEGIN{ if (u+0 > 0.86) exit 1; exit 0 }' || \
  printf '\033[33m! UTIL=%s > approved GLM-5.2 exception 0.86\033[0m\n' "$UTIL"

DRYRUN=0; STOP=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRYRUN=1 ;;
    --stop)    STOP=1 ;;
    *) die "unknown arg: $a (use --dry-run or --stop)" ;;
  esac
done

NNODES="${#NODES_ARR[@]}"
HEAD="${NODES_ARR[0]}"
NODES=("${NODES_ARR[@]}")

if [ "$STOP" = 1 ]; then
  say "stopping '$NAME' on all ${NNODES} nodes"
  for ip in "${NODES[@]}"; do
    key_args=(); [ -f "$SSH_KEY" ] && key_args=(-i "$SSH_KEY")
    ssh "${key_args[@]}" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      "$(node_user "$ip")@$ip" "docker rm -f $NAME 2>/dev/null" \
      && printf '   stopped on %s\n' "$ip"
  done
  exit 0
fi

ENVV=(
  -e "VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS=1800"
  -e "LD_PRELOAD=/cache/huggingface/hub/nccl-2.30.4/libnccl.so.2"
  -e "HF_HOME=/cache/huggingface"
  -e "TRITON_CACHE_DIR=/cache/huggingface/.tritoncache"
  -e "HF_HUB_OFFLINE=1"
  -e "VLLM_ALLOW_LONG_MAX_MODEL_LEN=1"
  -e "VLLM_SPARSE_INDEXER_MAX_LOGITS_MB=256"
  -e "GLM52_BIND_HOST_TRITON=1"
  -e "GLM52_MQA_LOGITS_TRITON=1"
  -e "GLM52_PAGED_MQA_TRITON=1"
  -e "GLM52_PAGED_MQA_TOPK_CHUNK_SIZE=8192"
  -e "GLM52_B12X_MLA=1"
  -e "TORCH_CUDA_ARCH_LIST=12.1a"
  -e "VLLM_MARLIN_USE_ATOMIC_ADD=${VLLM_MARLIN_USE_ATOMIC_ADD:-1}"
  -e "NCCL_NET=IB"
  -e "NCCL_IB_DISABLE=0"
  -e "NCCL_IB_HCA=$NCCL_IB_HCA"
  -e "NCCL_SOCKET_IFNAME=$NCCL_SOCKET_IFNAME"
  -e "GLOO_SOCKET_IFNAME=$GLOO_SOCKET_IFNAME"
  -e "NCCL_IB_GID_INDEX=$NCCL_IB_GID_INDEX"
  -e "NCCL_MAX_NCHANNELS=4"
  -e "NCCL_MIN_NCHANNELS=4"
  -e "NCCL_CROSS_NIC=1"
  -e "NCCL_CUMEM_ENABLE=0"
  -e "NCCL_IGNORE_CPU_AFFINITY=1"
  -e "NCCL_DEBUG=WARN"
)

MLA="/usr/local/lib/python3.12/dist-packages/vllm/v1/attention/backends/mla"
OPS="/usr/local/lib/python3.12/dist-packages/vllm/v1/attention/ops/deepseek_v4_ops"
LAYERS="/usr/local/lib/python3.12/dist-packages/vllm/model_executor/layers"
MODELS="/usr/local/lib/python3.12/dist-packages/vllm/model_executor/models"
KMOUNTS=(
  -v "$KERNELS_DIR/sparse_mla_kernels.py:$MLA/sparse_mla_kernels.py:ro"
  -v "$KERNELS_DIR/sparse_mla_env.py:$MLA/sparse_mla_env.py:ro"
  -v "$KERNELS_DIR/sm12x_sparse_mla_attn.py:$MLA/sm12x_sparse_mla_attn.py:ro"
  -v "$KERNELS_DIR/patch_flashmla_ops.py:$MLA/patch_flashmla_ops.py:ro"
  -v "$KERNELS_DIR/flashmla_sparse.py:$MLA/flashmla_sparse.py:ro"
  -v "$KERNELS_DIR/sm12x_deep_gemm_fallbacks.py:$OPS/sm12x_deep_gemm_fallbacks.py:ro"
  -v "$KERNELS_DIR/sm12x_mqa.py:$OPS/sm12x_mqa.py:ro"
  -v "$KERNELS_DIR/b12x_sparse_helpers.py:$OPS/b12x_sparse_helpers.py:ro"
  -v "$KERNELS_DIR/sparse_attn_indexer.py:$LAYERS/sparse_attn_indexer.py:ro"
  -v "$KERNELS_DIR/deepseek_v2.py:$MODELS/deepseek_v2.py:ro"
)
# Optional tonyd/GB10 extras if present in kernels/
if [ -f "$KERNELS_DIR/indexer.py" ]; then
  KMOUNTS+=(-v "$KERNELS_DIR/indexer.py:$MLA/indexer.py:ro")
fi
if [ -f "$KERNELS_DIR/deepseek_mtp.py" ]; then
  KMOUNTS+=(-v "$KERNELS_DIR/deepseek_mtp.py:$MODELS/deepseek_mtp.py:ro")
fi

BASE=(
  --cap-add IPC_LOCK --ulimit memlock=-1:-1
  --network host --ipc host --shm-size 10gb --gpus all
  --device /dev/infiniband:/dev/infiniband
  -v "$WEIGHTS_DIR:/cache/huggingface"
  -v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro
)

SERVE=(
  vllm serve /cache/huggingface/hub/glm52-int4-int8mix
  --served-model-name glm-5.2 --host 0.0.0.0 --port "$PORT"
  --trust-remote-code --reasoning-parser glm45 --tool-call-parser glm47 --enable-auto-tool-choice
  --enable-prefix-caching
  --async-scheduling
  --speculative-config "{\"method\":\"mtp\",\"num_speculative_tokens\":${MTP_K},\"draft_tensor_parallel_size\":1,\"attention_backend\":\"FLASHMLA_SPARSE\"}"
  --tensor-parallel-size 4 --pipeline-parallel-size 1
  --max-model-len "$MAX_MODEL_LEN" --max-num-seqs "$MAX_NUM_SEQS" --max-num-batched-tokens 8192
  --gpu-memory-utilization "$UTIL" --kv-cache-memory-bytes "$KV_BYTES"
  --kv-cache-dtype fp8_ds_mla
  --distributed-executor-backend mp --compilation-config '{"cudagraph_mode":"FULL","pass_config":{"fuse_gemm_comms":true}}'
)

docker_run_cmd() {
  local rank="$1" headless="$2"
  local cmd=(docker run -d --name "$NAME" "${BASE[@]}" "${ENVV[@]}" "${KMOUNTS[@]}"
             -e "NODE_RANK=$rank" -e "MASTER_ADDR=$HEAD"
             "$IMAGE" "${SERVE[@]}"
             --nnodes "$NNODES" --node-rank "$rank" --master-addr "$HEAD" --master-port "$MASTER_PORT")
  [ "$headless" = 1 ] && cmd+=(--headless)
  local out="" t
  for t in "${cmd[@]}"; do out+=" $(printf '%q' "$t")"; done
  printf '%s' "${out# }"
}

say "Quantrio ablit: ${NNODES} nodes head=$HEAD:$PORT image=$IMAGE len=$MAX_MODEL_LEN UTIL=$UTIL KV=$KV_BYTES"
echo "   fabric: HCA=$NCCL_IB_HCA ifname=$NCCL_SOCKET_IFNAME gid=$NCCL_IB_GID_INDEX"
echo "   nodes:  ${NODES[*]}"
[ "$DRYRUN" = 1 ] && echo "   (dry-run — nothing will be executed)"

# Workers first (rank 1..N-1 headless), then head rank 0.
for ((rank=1; rank<NNODES; rank++)); do
  w="${NODES[$rank]}"
  run="$(docker_run_cmd "$rank" 1)"
  shell="docker rm -f $NAME 2>/dev/null; $run"
  if [ "$DRYRUN" = 1 ]; then
    printf '\n# worker %s (rank %d, headless)\nssh %s@%s %q\n' "$w" "$rank" "$(node_user "$w")" "$w" "$shell"
  else
    printf '   worker %s rank=%d (headless)\n' "$w" "$rank"
    key_args=(); [ -f "$SSH_KEY" ] && key_args=(-i "$SSH_KEY")
    ssh "${key_args[@]}" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      "$(node_user "$w")@$w" "$shell" \
      || die "worker launch failed on $w"
  fi
done

run="$(docker_run_cmd 0 0)"
shell="docker rm -f $NAME 2>/dev/null; $run"
if [ "$DRYRUN" = 1 ]; then
  printf '\n# head %s (rank 0)\n%s\n' "$HEAD" "$shell"
  exit 0
fi
printf '   head %s rank=0\n' "$HEAD"
bash -c "$shell" || die "head launch failed"

say "launched"
echo "   poll:  curl -s http://$HEAD:$PORT/v1/models"
echo "   logs:  docker logs -f $NAME   (on head $HEAD)"
echo "   stop:  $0 --stop"
echo "   Ready in ~12 min load + ~10 min cudagraph warmup; serves as 'glm-5.2'."
echo "   Tip: during load, periodic drop_caches on all nodes helps GB10 reclaim stalls."
