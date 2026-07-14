#!/usr/bin/env bash
#
# launch.sh — start GLM-5.2 (TP=4) across a 4-node GB10 / DGX Spark cluster.
#
# Derived from launch.sh in CosmicRaisins/glm-5.2-gb10
# (https://github.com/CosmicRaisins/glm-5.2-gb10), Copyright (c) CosmicRaisins,
# licensed under the Apache License, Version 2.0. Adaptations for the unpruned
# QuantTrio Int4-Int8Mix checkpoint at 200K context. See NOTICE.
#
# Self-contained: a plain `docker run` per node, no external harness. Multi-node
# is vLLM's NATIVE mechanism (--nnodes/--node-rank/--master-addr/--master-port);
# the workers (rank >= 1) start headless, then the head (rank 0) serves the API.
# There is NO Ray and NO shared-filesystem requirement — each node just needs the
# weights present locally (see WEIGHTS_DIR) and the kernels deployed to
# KERNELS_DIR (see README step "Kernels").
#
# Run from the HEAD node (NODES[0]). Workers are reached over key-based SSH.
#
#   ./launch.sh            # launch
#   ./launch.sh --dry-run  # print the docker commands without running them
#   ./launch.sh --stop     # docker rm -f the container on every node
#
# License: Apache-2.0.
set -uo pipefail

# ============================================================================
# CONFIG — edit these for your cluster
# ============================================================================
# EDIT: RoCE rail IPs, rank 0 (head) FIRST. Run this script from the head node.
# (Our fabric: a CRS812 switch on 192.168.192.0/24, MTU 9000.)
NODES=(10.100.10.4 10.100.10.1 10.100.10.2 10.100.10.3)

# EDIT: SSH key the head node uses to reach the workers (key-based, no prompt).
SSH_KEY="$HOME/.ssh/id_ed25519"

# EDIT: how to derive the SSH username for a given node IP. If every node uses
# the same user, just `echo` it. Our cluster numbers users by the last octet
# (192.168.192.1 -> tonyspark1, .2 -> tonyspark2, ...), i.e.:
#   node_user() { echo "tonyspark${1##*.}"; }
node_user() { echo "keyspark"; }

IMAGE="vllm-node-tf5-glm52-dcp:e232-modded"
NAME="vllm_slot"                         # container name on every node
PORT=8210                                # OpenAI API port on the head node
MASTER_PORT=29501                        # vLLM cross-node rendezvous port

# Weights. A directory THAT EXISTS ON EVERY NODE, holding the HF hub layout:
#   $WEIGHTS_DIR/hub/glm52-int4-int8mix       (QuantTrio Int4-Int8Mix weights,
#                                              symlink -> ../glm52-int4-int8mix)
#   $WEIGHTS_DIR/hub/nccl-2.30.4/libnccl.so.2 (LD_PRELOADed NCCL, see README)
# Mounted writable at /cache/huggingface (HF_HOME) so JIT/Triton caches stay local.
# How the weights get onto each node is YOUR choice — per-node copy, rsync, or a
# shared mount pointed here. This script does not assume any of them.
WEIGHTS_DIR="/var/tmp/models"

# Per-node directory holding the 10 Triton sparse-MLA kernel .py files from
# CosmicRaisins/glm-5.2-gb10 kernels/. Bound file-by-file over the vLLM tree,
# read-only.
KERNELS_DIR="$HOME/glm-triton"
# ============================================================================

say()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
die()  { printf '\n\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

DRYRUN=0; STOP=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRYRUN=1 ;;
    --stop)    STOP=1 ;;
    *) die "unknown arg: $a (use --dry-run or --stop)" ;;
  esac
done

[ "${#NODES[@]}" -ge 1 ] || die "NODES is empty"
NNODES="${#NODES[@]}"
HEAD="${NODES[0]}"

if [ "$STOP" = 1 ]; then
  say "stopping '$NAME' on all ${NNODES} nodes"
  for ip in "${NODES[@]}"; do
    ssh -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$(node_user "$ip")@$ip" "docker rm -f $NAME 2>/dev/null" \
      && printf '   stopped on %s\n' "$ip"
  done
  exit 0
fi

# ----------------------------------------------------------------------------
# Container env. The NCCL_IB_HCA / *_SOCKET_IFNAME values are RoCE-fabric-
# specific: set them for YOUR cluster (HCAs via `ibdev2netdev`, interfaces via
# `ip link`). Marked EDIT.
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
  # Force the b12x sparse-indexer path ON at model-build time so deepseek_v2.py allocates
  # topk_scores_buffer (DCP needs it at decode). Without this, use_b12x_sparse_indexer()
  # reads attention_config.backend via get_current_vllm_config_or_none() which is None
  # during model construction -> buffer skipped -> decode aborts "DCP requires topk_scores_buffer".
  -e "VLLM_USE_B12X_SPARSE_INDEXER=1"
  -e "TORCH_CUDA_ARCH_LIST=12.1a"
  -e "NCCL_NET=IB"
  -e "NCCL_IB_DISABLE=0"
  -e "NCCL_IB_HCA=rocep1s0f1"          # EDIT: your RoCE HCA (`ibdev2netdev`)
  -e "NCCL_SOCKET_IFNAME=enp1s0f1np1"  # EDIT: your fabric interface (`ip link`)
  -e "GLOO_SOCKET_IFNAME=enp1s0f1np1"  # EDIT: same fabric interface
  -e "NCCL_IB_GID_INDEX=3"             # EDIT if your RoCEv2 GID differs (`show_gids`)
  -e "NCCL_MAX_NCHANNELS=4"
  -e "NCCL_MIN_NCHANNELS=4"
  -e "NCCL_CROSS_NIC=1"
  -e "NCCL_CUMEM_ENABLE=0"
  -e "NCCL_IGNORE_CPU_AFFINITY=1"
  -e "NCCL_DEBUG=WARN"
)

# Triton sparse-MLA kernels, bound read-only over the vLLM tree (matches
# GLM52_BIND_HOST_TRITON=1). Paths are inside the image's vLLM install.
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
  # GB10 fix: B12X_MLA_SPARSE (DCP path) calls index_topk_fp8(out_scores=...) which the
  # sm12x-pinned b12x 0.23.0 lacks. Override the whole b12x package with 0.30.0 (has
  # out_scores, PAGED_INDEX_PAGE_SIZE=64 contract match, pure-python).
  -v "$HOME/b12x-0.30.0/b12x:/usr/local/lib/python3.12/dist-packages/b12x:ro"
  # GB10 fix/diagnostic: instrumented indexer.py recomputes the decode/prefill split
  # when the memoized result doesn't sum (MTP+DCP draft path). Includes tonyd overhang patch.
  -v "$KERNELS_DIR/indexer.py:$MLA/indexer.py:ro"
  # GB10 fix: patched deepseek_mtp.py adds packed_modules_mapping[fused_qkv_a_proj]
  # so the MTP draft loads QuantTrio Int4 (weight_packed) instead of KeyError-ing.
  -v "$KERNELS_DIR/deepseek_mtp.py:$MODELS/deepseek_mtp.py:ro"
  # NOTE: sparse_attn_indexer.py and deepseek_v2.py bind-mounts REMOVED for the DCP
  # branch (e232d262). The branch's own files are DCP-aware (VLLM_DCP_SHARD_DRAFT) and
  # define use_b12x_sparse_indexer (imported by deepseek_mtp.py); the CosmicRaisins
  # ab666069-era versions lack both and crash the engine at import. In-image
  # sparse_attn_indexer.py already carries the sm12x patch.
)

# docker run base — IB passthrough is REQUIRED (without --device=/dev/infiniband
# + IPC_LOCK + memlock, NCCL silently drops to TCP: ~12 vs 30+ tok/s).
BASE=(
  --cap-add IPC_LOCK --ulimit memlock=-1:-1
  --network host --ipc host --shm-size 10gb --gpus all
  --device /dev/infiniband:/dev/infiniband
  -v "$WEIGHTS_DIR:/cache/huggingface"
  -v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro
)

# The serving command, with {port} resolved.
# NOTE: --max-num-seqs 6 requires the indexer MTP-overhang patch baked into the
# image (patches/fix-indexer-mtp-overhang.py, README step h) — unpatched vLLM
# crashes at >= 3 concurrent requests with MTP enabled.
SERVE=(
  vllm serve /cache/huggingface/hub/glm52-int4-int8mix
  --served-model-name glm-5.2 --host 0.0.0.0 --port "$PORT"
  --trust-remote-code --reasoning-parser glm45 --tool-call-parser glm47 --enable-auto-tool-choice
  --enable-prefix-caching
  --async-scheduling
  --speculative-config '{"method":"mtp","num_speculative_tokens":4,"draft_tensor_parallel_size":1,"attention_backend":"B12X_MLA_SPARSE"}'
  --tensor-parallel-size 4 --pipeline-parallel-size 1
  --decode-context-parallel-size 4
  # At util 0.86, 98 GiB weights + DCP(4x-head) b12x workspace + activations leave
  # ~1.46 GiB/rank for KV -> vLLM's exact estimate is max ~100608 tokens (DCP-sharded).
  # 96K (98304) fits deterministically with margin. max-num-batched-tokens 2048 to
  # keep activation overhead low. This is the max context achievable at 0.86 + DCP=4.
  --max-model-len 65536 --max-num-seqs 6 --max-num-batched-tokens 2048
  --gpu-memory-utilization 0.86
  --kv-cache-dtype fp8_ds_mla
  # DCP needs the decode attention to return softmax LSE. Default sm_121a sparse pick
  # is FLASHMLA_SPARSE (no LSE) -> DCP aborts. Force B12X_MLA_SPARSE (can_return_lse_for_decode,
  # full DCP plumbing, valid on major==12 + index_topk + fp8_ds_mla). Env VLLM_ATTENTION_BACKEND
  # is unknown on this branch; the CLI flag is the working mechanism.
  --attention-backend B12X_MLA_SPARSE
  # enforce-eager REQUIRED: cudagraph (even FULL_AND_PIECEWISE) crashes the b12x sparse DCP
  # indexer under MTP's non-uniform drafting batches (page_table/seqlens row mismatch; backend
  # only supports UNIFORM_BATCH graphs). DCP+MTP is therefore eager-only on this branch.
  --distributed-executor-backend mp --enforce-eager
)

# Build the full `docker run` for a given rank, as a single shell-quoted string.
docker_run_cmd() {
  local rank="$1" headless="$2"
  local cmd=(docker run -d --name "$NAME" "${BASE[@]}" "${ENVV[@]}" "${KMOUNTS[@]}"
             -e "NODE_RANK=$rank" -e "MASTER_ADDR=$HEAD"
             "$IMAGE" "${SERVE[@]}"
             --nnodes "$NNODES" --node-rank "$rank" --master-addr "$HEAD" --master-port "$MASTER_PORT")
  [ "$headless" = 1 ] && cmd+=(--headless)
  # printf %q on each token yields a paste-safe, correctly-quoted command line.
  local out="" t
  for t in "${cmd[@]}"; do out+=" $(printf '%q' "$t")"; done
  printf '%s' "${out# }"
}

say "GLM-5.2 launch: ${NNODES} nodes, head=$HEAD:$PORT, image=$IMAGE"
[ "$DRYRUN" = 1 ] && echo "   (dry-run — nothing will be executed)"

# Workers first (rank 1..N-1, headless), then the head (rank 0).
for ((rank=1; rank<NNODES; rank++)); do
  w="${NODES[$rank]}"
  run="$(docker_run_cmd "$rank" 1)"
  shell="docker rm -f $NAME 2>/dev/null; $run"
  if [ "$DRYRUN" = 1 ]; then
    printf '\n# worker %s (rank %d, headless)\nssh %s@%s %q\n' "$w" "$rank" "$(node_user "$w")" "$w" "$shell"
  else
    printf '   worker %s rank=%d (headless)\n' "$w" "$rank"
    ssh -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$(node_user "$w")@$w" "$shell" \
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
echo "   poll:  curl -s http://localhost:$PORT/v1/models"
echo "   logs:  docker logs -f $NAME   (on the head node)"
echo "   stop:  ./launch.sh --stop"
echo "   Ready in ~12 min load + ~10 min cudagraph warmup; serves as 'glm-5.2'."
