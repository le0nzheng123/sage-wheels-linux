#!/usr/bin/env bash
# build-multi-sm.sh — Build one Linux SageAttention wheel for multiple CUDA architectures.
#
# Existing single-SM scripts are intentionally independent from this entrypoint.
#
# Usage:
#   ./build-multi-sm.sh
#   SM_LIST="80 86 89 120" ./build-multi-sm.sh
#
# Defaults:
#   SM_LIST="80 86 89" (A100/A800, RTX 30xx, RTX 40xx)
#   OUT_DIR=./dist-multi-sm

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SM_LIST="${SM_LIST:-80 86 89}"
SAGE_REF="${SAGE_REF:-v2.2.0}"
SAGE_COMMIT="${SAGE_COMMIT:-eb615cf6cf4d221338033340ee2de1c37fbdba4a}"
BASE_IMAGE="${BASE_IMAGE:-}"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/dist-multi-sm}"
MAX_JOBS="${MAX_JOBS:-4}"
BUILD_BACKEND="${BUILD_BACKEND:-auto}"
CLEAN_OUT_DIR="${CLEAN_OUT_DIR:-1}"
AUTO_BUILDER=0

case "$BUILD_BACKEND" in
    docker|native|auto) ;;
    *) echo "ERROR: BUILD_BACKEND must be one of: docker, native, auto" >&2; exit 1 ;;
esac

read -r -a SM_VALUES <<< "$SM_LIST"
if [ "${#SM_VALUES[@]}" -eq 0 ]; then
    echo "ERROR: SM_LIST must contain at least one architecture" >&2
    exit 1
fi

ARCH_VALUES=()
NORMALIZED_SM_VALUES=()
SEEN_SMS=" "
for sm in "${SM_VALUES[@]}"; do
    case "$sm" in
        75)
            echo "ERROR: SM75 (RTX 20xx/T4) is intentionally excluded from SageAttention v2.2.0." >&2
            exit 2
            ;;
        80) arch="8.0" ;;
        86) arch="8.6" ;;
        89) arch="8.9" ;;
        90) arch="9.0" ;;
        120) arch="12.0" ;;
        *) echo "ERROR: SM '$sm' is not supported by this script." >&2; exit 1 ;;
    esac
    case "$SEEN_SMS" in
        *" $sm "*) echo "ERROR: duplicate architecture in SM_LIST: $sm" >&2; exit 1 ;;
    esac
    SEEN_SMS="${SEEN_SMS}${sm} "
    NORMALIZED_SM_VALUES+=("$sm")
    ARCH_VALUES+=("$arch")
done

NORMALIZED_SM_LIST="${NORMALIZED_SM_VALUES[*]}"
TORCH_CUDA_ARCH_LIST="$(IFS=';'; echo "${ARCH_VALUES[*]}")"
MULTI_SM_LABEL="$(printf 'sm%s-' "${NORMALIZED_SM_VALUES[@]}")"
MULTI_SM_LABEL="${MULTI_SM_LABEL%-}"

RESOLVED_BUILD_BACKEND="$BUILD_BACKEND"
if [ "$BUILD_BACKEND" = "auto" ]; then
    if ! command -v docker >/dev/null 2>&1; then
        RESOLVED_BUILD_BACKEND="native"
    elif [ -f /.dockerenv ] || grep -qaE '(docker|kubepods|containerd|lxc)' /proc/1/cgroup 2>/dev/null; then
        RESOLVED_BUILD_BACKEND="native"
    else
        RESOLVED_BUILD_BACKEND="docker"
    fi
fi

if [ "$RESOLVED_BUILD_BACKEND" = "docker" ] && [ -z "$BASE_IMAGE" ]; then
    TORCH_VER="${TORCH_VER:-2.13.0}"
    CUDA_TAG="${CUDA_TAG:-cu130}"
    PY_TAG="${PY_TAG:-cp313}"
    BASE_IMAGE="$(
        TORCH_VER="$TORCH_VER" \
        CUDA_TAG="$CUDA_TAG" \
        PY_TAG="$PY_TAG" \
        "$SCRIPT_DIR/prepare-builder.sh"
    )"
    AUTO_BUILDER=1
fi

if [ "$RESOLVED_BUILD_BACKEND" = "native" ]; then
    if [ -z "${TORCH_VER:-}" ] || [ -z "${CUDA_TAG:-}" ] || [ -z "${PY_TAG:-}" ]; then
        detected="$(python - <<'PY' 2>/dev/null || true
import sys
try:
    import torch
    torch_version = torch.__version__.split("+")[0]
    cuda_version = (torch.version.cuda or "").replace(".", "")
except Exception:
    torch_version, cuda_version = "", ""
python_tag = f"cp{sys.version_info.major}{sys.version_info.minor}"
print(f"{torch_version}|{cuda_version}|{python_tag}")
PY
)"
        detected_torch="${detected%%|*}"
        detected_rest="${detected#*|}"
        detected_cuda="${detected_rest%%|*}"
        detected_python="${detected_rest#*|}"
        TORCH_VER="${TORCH_VER:-${detected_torch:-2.13.0}}"
        CUDA_TAG="${CUDA_TAG:-cu${detected_cuda:-130}}"
        PY_TAG="${PY_TAG:-${detected_python:-cp313}}"
    fi
else
    image_tag="${BASE_IMAGE##*:}"
    image_torch="$(echo "$image_tag" | sed -nE 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')"
    image_cuda="$(echo "$image_tag" | sed -nE 's/.*cuda([0-9]+)\.([0-9]+).*/\1\2/p')"
    TORCH_VER="${TORCH_VER:-${image_torch:-2.13.0}}"
    CUDA_TAG="${CUDA_TAG:-cu${image_cuda:-130}}"
    PY_TAG="${PY_TAG:-cp313}"
fi

mkdir -p "$OUT_DIR"
if [ "$CLEAN_OUT_DIR" = "1" ]; then
    find "$OUT_DIR" -maxdepth 1 -type f \
        \( -name 'sageattention-*.whl' -o -name 'SHA256SUMS' \) -delete
fi

echo "==> Building one SageAttention Multi-SM wheel"
echo "    SAGE_REF             = $SAGE_REF"
echo "    SAGE_COMMIT          = $SAGE_COMMIT"
echo "    SM_LIST              = $NORMALIZED_SM_LIST"
echo "    TORCH_CUDA_ARCH_LIST = $TORCH_CUDA_ARCH_LIST"
echo "    TORCH_VER            = $TORCH_VER"
echo "    CUDA_TAG             = $CUDA_TAG"
echo "    PY_TAG               = $PY_TAG"
echo "    BUILD_BACKEND        = $RESOLVED_BUILD_BACKEND"
echo "    BASE_IMAGE           = ${BASE_IMAGE:-native environment}"
echo "    OUT_DIR              = $OUT_DIR"

if [ "$RESOLVED_BUILD_BACKEND" = "docker" ]; then
    SKIP_APT_VALUE="${SKIP_APT:-$AUTO_BUILDER}"
    SKIP_PIP_DEPS_VALUE="${SKIP_PIP_DEPS:-$AUTO_BUILDER}"
    docker run --rm \
        -e PIP_BREAK_SYSTEM_PACKAGES=1 \
        -e PIP_NO_CACHE_DIR=1 \
        -e OUT_DIR=/out \
        -e TORCH_CUDA_ARCH_LIST="$TORCH_CUDA_ARCH_LIST" \
        -e SM_LIST="$NORMALIZED_SM_LIST" \
        -e MAX_JOBS="$MAX_JOBS" \
        -e SAGE_REF="$SAGE_REF" \
        -e SAGE_COMMIT="$SAGE_COMMIT" \
        -e BUILDER_REQUIREMENTS=/requirements-builder.txt \
        -e EXPECTED_TORCH_VER="$TORCH_VER" \
        -e EXPECTED_CUDA_TAG="$CUDA_TAG" \
        -e EXPECTED_PY_TAG="$PY_TAG" \
        -e SKIP_APT="$SKIP_APT_VALUE" \
        -e SKIP_PIP_DEPS="$SKIP_PIP_DEPS_VALUE" \
        -v "$OUT_DIR:/out" \
        -v "$SCRIPT_DIR/build-wheel-multi-sm.sh:/build-wheel-multi-sm.sh:ro" \
        -v "$SCRIPT_DIR/.github/docker/requirements-builder.txt:/requirements-builder.txt:ro" \
        "$BASE_IMAGE" bash /build-wheel-multi-sm.sh
else
    export TORCH_CUDA_ARCH_LIST NORMALIZED_SM_LIST MAX_JOBS SAGE_REF SAGE_COMMIT OUT_DIR
    export BUILDER_REQUIREMENTS="$SCRIPT_DIR/.github/docker/requirements-builder.txt"
    export SM_LIST="$NORMALIZED_SM_LIST"
    export EXPECTED_TORCH_VER="$TORCH_VER"
    export EXPECTED_CUDA_TAG="$CUDA_TAG"
    export EXPECTED_PY_TAG="$PY_TAG"
    bash "$SCRIPT_DIR/build-wheel-multi-sm.sh"
fi

wheel_count="$(find "$OUT_DIR" -maxdepth 1 -name 'sageattention-*.whl' | wc -l | tr -d ' ')"
if [ "$wheel_count" != "1" ]; then
    echo "ERROR: expected exactly one Multi-SM wheel, found $wheel_count" >&2
    exit 1
fi

(cd "$OUT_DIR" && sha256sum sageattention-*.whl > SHA256SUMS)
echo "==> Multi-SM wheel ready ($MULTI_SM_LABEL)"
ls -lh "$OUT_DIR"/sageattention-*.whl "$OUT_DIR/SHA256SUMS"
