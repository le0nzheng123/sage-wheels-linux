#!/usr/bin/env bash
# build-all.sh — Build wheels for every arch in SM_LIST and generate SHA256SUMS.
#
# Variables exported to build.sh:
#   SAGE_REF       (default: v2.2.0)
#   SAGE_COMMIT    Expected commit for SAGE_REF
#   TORCH_VER      (default: 2.13.0)
#   CUDA_TAG       (default: cu130)
#   PY_TAG         (default: cp313)
#   BASE_IMAGE     Optional prebuilt Docker image. When omitted, build.sh
#                  creates/reuses the Python 3.13 builder automatically.
#   BUILD_BACKEND  (default: auto; values: docker|native|auto)
#   OUT_DIR        (default: ./dist)
#   SM_LIST        Space-separated list (default: "80 86 89 90 120")
#   CLEAN_OUT_DIR  Remove old SageAttention wheels/checksums first (default: 1)
#
# On small runners (< 16 GB RAM), parallel builds of the _fused.so link step
# can OOM. This script runs sequentially to stay safe.

set -euo pipefail

cd "$(dirname "$0")"

export SAGE_REF="${SAGE_REF:-v2.2.0}"
export SAGE_COMMIT="${SAGE_COMMIT:-eb615cf6cf4d221338033340ee2de1c37fbdba4a}"
export BASE_IMAGE="${BASE_IMAGE:-}"
export BUILD_BACKEND="${BUILD_BACKEND:-auto}"
export OUT_DIR="${OUT_DIR:-$(pwd)/dist}"

# TORCH_VER / CUDA_TAG / PY_TAG: only export if the user set them. Otherwise
# build.sh auto-detects (from the running python in native mode, or by parsing
# $BASE_IMAGE in docker mode).
[ -n "${TORCH_VER:-}" ] && export TORCH_VER
[ -n "${CUDA_TAG:-}" ]  && export CUDA_TAG
[ -n "${PY_TAG:-}" ]    && export PY_TAG

SM_LIST="${SM_LIST:-80 86 89 90 120}"
CLEAN_OUT_DIR="${CLEAN_OUT_DIR:-1}"

mkdir -p "$OUT_DIR"

if [ "$CLEAN_OUT_DIR" = "1" ]; then
    find "$OUT_DIR" -maxdepth 1 -type f \
        \( -name 'sageattention-*.whl' -o -name 'SHA256SUMS' \) -delete
fi

echo "==================================="
echo "Building SageAttention wheels"
echo "  SAGE_REF   = $SAGE_REF"
echo "  SAGE_COMMIT = $SAGE_COMMIT"
echo "  TORCH_VER  = ${TORCH_VER:-auto}"
echo "  CUDA_TAG   = ${CUDA_TAG:-auto}"
echo "  PY_TAG     = ${PY_TAG:-auto}"
echo "  BASE_IMAGE = ${BASE_IMAGE:-auto Python 3.13 builder}"
echo "  BUILD_BACKEND = $BUILD_BACKEND"
echo "  SM_LIST    = $SM_LIST"
echo "  OUT_DIR    = $OUT_DIR"
echo "==================================="

read -r -a SM_VALUES <<< "$SM_LIST"
if [ "${#SM_VALUES[@]}" -eq 0 ]; then
    echo "ERROR: SM_LIST must contain at least one architecture" >&2
    exit 1
fi

for sm in "${SM_VALUES[@]}"; do
    echo
    echo ">>> sm${sm}"
    ./build.sh "$sm"
done

echo
echo "==> Generating SHA256SUMS"
( cd "$OUT_DIR" && sha256sum sageattention-*.whl > SHA256SUMS )
cat "$OUT_DIR/SHA256SUMS"

# If values weren't provided up front, detect them now so the suggested tag
# matches the wheels we just produced.
if [ -z "${TORCH_VER:-}" ] || [ -z "${CUDA_TAG:-}" ] || [ -z "${PY_TAG:-}" ]; then
    _detected="$(python - <<'PY' 2>/dev/null || true
import sys
try:
    import torch
    tv = torch.__version__.split("+")[0]
    cu = (torch.version.cuda or "").replace(".", "")
except Exception:
    tv, cu = "", ""
py = f"cp{sys.version_info.major}{sys.version_info.minor}"
print(f"{tv}|{cu}|{py}")
PY
)"
    _tv="${_detected%%|*}"; _rest="${_detected#*|}"
    _cu="${_rest%%|*}"; _py="${_rest#*|}"
    TORCH_VER="${TORCH_VER:-${_tv:-unknown}}"
    CUDA_TAG="${CUDA_TAG:-cu${_cu:-unknown}}"
    PY_TAG="${PY_TAG:-${_py:-cp313}}"
fi

echo
echo "==> Suggested tag:"
PY_DIGITS="${PY_TAG#cp}"
echo "    sage-<SAGE_VER>-torch-${TORCH_VER}-${CUDA_TAG}-py${PY_DIGITS}"
echo
echo "    (replace <SAGE_VER> with the exact version baked into the wheel filenames)"
echo
echo "==> Next: see BUILD.md → 'Publish release'"
