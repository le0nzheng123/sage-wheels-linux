#!/usr/bin/env bash
# build-wheel-multi-sm.sh — Build one Linux wheel containing multiple CUDA SM targets.

set -euo pipefail

: "${SM_LIST:?SM_LIST is required}"
: "${TORCH_CUDA_ARCH_LIST:?TORCH_CUDA_ARCH_LIST is required}"
: "${SAGE_REF:?SAGE_REF is required}"
: "${OUT_DIR:?OUT_DIR is required}"

MAX_JOBS="${MAX_JOBS:-4}"
SRC_DIR="${SRC_DIR:-/tmp/sage-multi-sm}"
WHEEL_TMP="${WHEEL_TMP:-/tmp/wheel-multi-sm}"

mkdir -p "$OUT_DIR"

if [ "${SKIP_APT:-0}" != "1" ] && command -v apt-get >/dev/null 2>&1; then
    echo "==> apt deps"
    if [ "$(id -u)" -eq 0 ]; then
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends git ca-certificates
    elif command -v sudo >/dev/null 2>&1; then
        sudo apt-get update -qq
        sudo apt-get install -y -qq --no-install-recommends git ca-certificates
    else
        echo "    non-root and sudo not available; skipping apt install"
    fi
fi

if [ "${SKIP_PIP_DEPS:-0}" != "1" ]; then
    echo "==> pip deps"
    python -m pip install -q --upgrade pip wheel setuptools
fi

command -v git
command -v python
command -v nvcc

echo "==> clone thu-ml/SageAttention @ $SAGE_REF"
if [ ! -d "$SRC_DIR/.git" ]; then
    rm -rf "$SRC_DIR"
    git clone https://github.com/thu-ml/SageAttention.git "$SRC_DIR"
fi

cd "$SRC_DIR"
git fetch --all --tags -q
git checkout "$SAGE_REF"
git clean -fdx
git reset --hard HEAD
echo "    commit: $(git rev-parse HEAD)"

echo "==> build environment"
nvcc --version
read -r ACTUAL_TORCH ACTUAL_CUDA ACTUAL_PY <<EOF
$(python - <<'PY'
import sys
import torch
from torch.utils.cpp_extension import CUDA_HOME
print(torch.__version__.split("+")[0], (torch.version.cuda or "").replace(".", ""), f"cp{sys.version_info.major}{sys.version_info.minor}")
print(f"CUDA_HOME={CUDA_HOME}", file=sys.stderr)
PY
)
EOF
echo "    torch=$ACTUAL_TORCH cuda=${ACTUAL_CUDA:-none} python=$ACTUAL_PY"
echo "    SM_LIST=$SM_LIST"
echo "    TORCH_CUDA_ARCH_LIST=$TORCH_CUDA_ARCH_LIST"

if [ -n "${EXPECTED_TORCH_VER:-}" ] && [ "$ACTUAL_TORCH" != "$EXPECTED_TORCH_VER" ]; then
    echo "ERROR: expected PyTorch $EXPECTED_TORCH_VER, found $ACTUAL_TORCH" >&2
    exit 1
fi
if [ -n "${EXPECTED_CUDA_TAG:-}" ]; then
    EXPECTED_CUDA="${EXPECTED_CUDA_TAG#cu}"
    if [ "$ACTUAL_CUDA" != "$EXPECTED_CUDA" ]; then
        echo "ERROR: expected CUDA ${EXPECTED_CUDA_TAG}, found cu${ACTUAL_CUDA:-none}" >&2
        exit 1
    fi
fi
if [ -n "${EXPECTED_PY_TAG:-}" ] && [ "$ACTUAL_PY" != "$EXPECTED_PY_TAG" ]; then
    echo "ERROR: expected Python ${EXPECTED_PY_TAG}, found ${ACTUAL_PY}" >&2
    exit 1
fi

# PyTorch 2.14 requires C++20 for C++/CUDA extensions, while SageAttention
# v2.2.0 still declares -std=c++17. Appending C++20 makes it the final
# standard flag without modifying the checked-out upstream source.
if [[ "$ACTUAL_TORCH" == 2.14.* ]]; then
    CXX_APPEND_FLAGS="${CXX_APPEND_FLAGS:+$CXX_APPEND_FLAGS }-std=c++20"
    NVCC_APPEND_FLAGS="${NVCC_APPEND_FLAGS:+$NVCC_APPEND_FLAGS }-std=c++20"
    export CXX_APPEND_FLAGS NVCC_APPEND_FLAGS
    echo "    compiler standard: C++20 (required by PyTorch $ACTUAL_TORCH)"
fi

echo "==> pip wheel (one wheel; SM $SM_LIST)"
mkdir -p "$WHEEL_TMP"
rm -f "$WHEEL_TMP"/sageattention-*.whl
python -m pip wheel . --no-build-isolation --no-deps -w "$WHEEL_TMP"

shopt -s nullglob
wheels=("$WHEEL_TMP"/sageattention-*.whl)
shopt -u nullglob
if [ "${#wheels[@]}" -ne 1 ]; then
    echo "ERROR: expected one wheel, found ${#wheels[@]}" >&2
    exit 1
fi

wheel="${wheels[0]}"
wheel_name="$(basename "$wheel")"
case "$wheel_name" in
    sageattention-*-cp*-cp*-linux_x86_64.whl) ;;
    *) echo "ERROR: unexpected wheel filename: $wheel_name" >&2; exit 1 ;;
esac

cp "$wheel" "$OUT_DIR/$wheel_name"
chown "$(stat -c %u:%g "$OUT_DIR")" "$OUT_DIR/$wheel_name" || true
echo "==> done: $wheel_name (SM $SM_LIST)"
