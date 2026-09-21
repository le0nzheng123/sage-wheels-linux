#!/usr/bin/env bash
# Build (or reuse) the local Python 3.13 + PyTorch + CUDA builder image.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TORCH_VER="${TORCH_VER:-2.13.0}"
CUDA_TAG="${CUDA_TAG:-cu130}"
PY_TAG="${PY_TAG:-cp313}"
PYTHON_VERSION="${PYTHON_VERSION:-3.13}"
CUDA_BASE_IMAGE="${CUDA_BASE_IMAGE:-nvidia/cuda:13.0.0-devel-ubuntu22.04}"
REBUILD_BUILDER="${REBUILD_BUILDER:-0}"

command -v docker >/dev/null 2>&1 || {
    echo "ERROR: Docker is required to prepare the builder image" >&2
    exit 1
}
docker info >/dev/null 2>&1 || {
    echo "ERROR: Docker daemon is not available" >&2
    exit 1
}

if command -v sha256sum >/dev/null 2>&1; then
    BUILDER_DEFINITION_HASH="$(sha256sum "$SCRIPT_DIR/.github/docker/Dockerfile.py313" | awk '{print substr($1,1,12)}')"
else
    BUILDER_DEFINITION_HASH="$(shasum -a 256 "$SCRIPT_DIR/.github/docker/Dockerfile.py313" | awk '{print substr($1,1,12)}')"
fi
BUILDER_IMAGE="${BUILDER_IMAGE:-sageattention-builder:torch-${TORCH_VER}-${CUDA_TAG}-${PY_TAG}-${BUILDER_DEFINITION_HASH}}"

case "$TORCH_VER" in
    2.13.0|2.14.0) ;;
    *) echo "ERROR: supported TORCH_VER values are 2.13.0 and 2.14.0" >&2; exit 1 ;;
esac

if [ "$CUDA_TAG" != "cu130" ]; then
    echo "ERROR: this builder currently supports CUDA_TAG=cu130 only" >&2
    exit 1
fi

if [ "$PY_TAG" != "cp313" ] || [ "$PYTHON_VERSION" != "3.13" ]; then
    echo "ERROR: this builder currently supports Python 3.13 / cp313 only" >&2
    exit 1
fi

if [ "$REBUILD_BUILDER" != "1" ] && docker image inspect "$BUILDER_IMAGE" >/dev/null 2>&1; then
    echo "==> Reusing builder image: $BUILDER_IMAGE" >&2
else
    echo "==> Building builder image: $BUILDER_IMAGE" >&2
    docker build \
        --build-arg "BASE_IMAGE=$CUDA_BASE_IMAGE" \
        --build-arg "TORCH_VERSION=$TORCH_VER" \
        --build-arg "PYTHON_VERSION=$PYTHON_VERSION" \
        --build-arg "CUDA_INDEX_URL=https://download.pytorch.org/whl/${CUDA_TAG}" \
        --tag "$BUILDER_IMAGE" \
        --file "$SCRIPT_DIR/.github/docker/Dockerfile.py313" \
        "$SCRIPT_DIR" >&2
fi

docker run --rm "$BUILDER_IMAGE" bash -lc '
    set -euo pipefail
    command -v python
    command -v nvcc
    python -c "import sys, torch, triton; print(sys.version); print(torch.__version__); print(torch.version.cuda); print(triton.__version__)"
    nvcc --version
' >&2

printf '%s\n' "$BUILDER_IMAGE"
