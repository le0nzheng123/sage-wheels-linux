#!/usr/bin/env bash
# Build (or reuse) the local Python 3.13 + PyTorch + CUDA builder image.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TORCH_VER="${TORCH_VER:-2.13.0}"
CUDA_TAG="${CUDA_TAG:-cu130}"
PY_TAG="${PY_TAG:-cp313}"
PYTHON_VERSION="${PYTHON_VERSION:-3.13}"
CUDA_BASE_IMAGE="${CUDA_BASE_IMAGE:-nvidia/cuda:13.0.0-devel-ubuntu22.04@sha256:1470d2d7904fac4e5cb3bdfd4993305c46d3ee76deb0213eaaf248e5cf9c7400}"
REBUILD_BUILDER="${REBUILD_BUILDER:-0}"
BUILDER_DOCKERFILE="$SCRIPT_DIR/.github/docker/Dockerfile.py313"
BUILDER_REQUIREMENTS="$SCRIPT_DIR/.github/docker/requirements-builder.txt"

command -v docker >/dev/null 2>&1 || {
    echo "ERROR: Docker is required to prepare the builder image" >&2
    exit 1
}
docker info >/dev/null 2>&1 || {
    echo "ERROR: Docker daemon is not available" >&2
    exit 1
}

if [[ ! "$CUDA_BASE_IMAGE" =~ @sha256:[0-9a-f]{64}$ ]]; then
    echo "ERROR: CUDA_BASE_IMAGE must be pinned by sha256 digest" >&2
    exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
    BUILDER_DEFINITION_HASH="$(
        { printf '%s\n' "$CUDA_BASE_IMAGE"; cat "$BUILDER_DOCKERFILE" "$BUILDER_REQUIREMENTS"; } \
            | sha256sum | awk '{print substr($1,1,12)}'
    )"
else
    BUILDER_DEFINITION_HASH="$(
        { printf '%s\n' "$CUDA_BASE_IMAGE"; cat "$BUILDER_DOCKERFILE" "$BUILDER_REQUIREMENTS"; } \
            | shasum -a 256 | awk '{print substr($1,1,12)}'
    )"
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
        --file "$BUILDER_DOCKERFILE" \
        "$SCRIPT_DIR" >&2
fi

docker run --rm "$BUILDER_IMAGE" bash -lc '
    set -euo pipefail
    command -v python
    command -v nvcc
    python -c "import sys, torch, triton; from importlib.metadata import version; expected={\"setuptools\":\"78.1.0\",\"wheel\":\"0.43.0\",\"packaging\":\"23.2\",\"ninja\":\"1.13.2\",\"auditwheel\":\"6.8.2\"}; actual={package:version(package) for package in expected}; mismatches={package:(expected[package], actual[package]) for package in expected if actual[package] != expected[package]}; assert not mismatches, mismatches; print(sys.version); print(torch.__version__); print(torch.version.cuda); print(triton.__version__); print(\"builder tooling:\", actual)"
    nvcc --version
' >&2

printf '%s\n' "$BUILDER_IMAGE"
