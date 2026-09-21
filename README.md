# SageAttention Linux 预编译 Wheel

本项目用于构建适配 ComfyUI 运行环境的 SageAttention 2.x Linux wheel。

上游 SageAttention 包含 C++/CUDA 扩展。构建时需要 CUDA Toolkit 和
`nvcc`，但把已经编译好的 `.whl` 安装到 ComfyUI 运行服务器时，通常不需要
安装 `nvcc`。

上游项目：

- [SageAttention](https://github.com/thu-ml/SageAttention)
- [SageAttention v2.2.0](https://github.com/thu-ml/SageAttention/tree/v2.2.0)

## 为什么要调整 PyTorch/Python 版本

这里的版本调整主要是为了跟随 ComfyUI 的 release 和官方依赖要求，而不是
单独为了升级 SageAttention。

ComfyUI 官方当前要求和建议包括：

| 组件 | ComfyUI 相关要求 |
|---|---|
| Python | Python 3.13 推荐；部分自定义节点不兼容时可以使用 Python 3.12 |
| PyTorch | PyTorch 2.7 是最低支持版本，建议使用更新版本 |
| NVIDIA PyTorch | 使用 CUDA 13.0 或更高版本的 PyTorch wheel |
| CUDA Toolkit / `nvcc` | 普通运行 ComfyUI 不需要；编译 CUDA 扩展时需要 |
| ComfyUI 依赖 | 以对应 ComfyUI release 的 `requirements.txt` 为准 |

因此，本项目中的 PyTorch 版本不是永久固定的。ComfyUI release、Python、
PyTorch 或 CUDA 组合发生变化时，应增加匹配的 SageAttention 构建配置。

当前项目保留以下构建配置：

| SageAttention | PyTorch | CUDA | Python | 构建状态 |
|---|---|---|---|---|
| 2.2.0 | 2.13.0 | cu130 | 3.13 | 默认配置 |
| 2.2.0 | 2.14.0 | cu130 | 3.13 | 可选配置，需重新构建和验证 |

其中 `cu130` 表示 PyTorch wheel 搭配 CUDA 13.0 运行库，不代表 ComfyUI
运行服务器必须安装系统级 `nvcc`。

## GPU 架构范围

SageAttention v2.2.0 上游源码支持以下 CUDA Compute Capability：

| SM | GPU 示例 | 本项目状态 |
|---:|---|---|
| 80 | A100/A800 | 支持 |
| 86 | RTX 3060/3080/3090、A10/A40 | 支持 |
| 89 | RTX 4090、L40/L40S | 支持 |
| 90 | H100/H200 | 支持 |
| 120 | RTX 50xx、B200 | 支持 |
| 75 | RTX 20xx、T4 | 暂不支持，已从默认矩阵移除 |

RTX 20xx 的 SM75 不纳入 SageAttention v2.2.0 构建。项目脚本会主动拒绝
`SM75`，避免生成看似成功但缺少对应 SageAttention CUDA kernel 的 wheel。

注意：SageAttention 是 Attention 后端，不是多卡调度器。它不会自动把
ComfyUI 任务拆分到多张 GPU。每个运行进程仍需使用正确的 GPU 和对应 SM
架构 wheel。

## Wheel 文件命名

Release 标签格式：

```text
sage-<SAGE_VER>-torch-<TORCH_VER>-<CUDA_TAG>-py<PY_VER>
```

例如：

```text
sage-2.2.0-torch-2.13.0-cu130-py313
```

Wheel 文件格式：

```text
sageattention-<SAGE_VER>-<SM>-cp<PYMM>-cp<PYMM>-linux_x86_64.whl
```

例如：

```text
sageattention-2.2.0-86-cp313-cp313-linux_x86_64.whl
sageattention-2.2.0-89-cp313-cp313-linux_x86_64.whl
sageattention-2.2.0-120-cp313-cp313-linux_x86_64.whl
```

文件名中的 `cp313` 表示 Python 3.13 ABI，数字 `86/89/120` 表示目标 GPU
架构。

## 两种构建环境

### Docker 构建

构建机需要 Docker、网络、足够的磁盘和内存，但不需要显卡，也不需要在
宿主机安装 `nvcc`：

```bash
BUILD_BACKEND=docker ./build-all.sh
```

未指定 `BASE_IMAGE` 时，脚本会通过 `prepare-builder.sh` 自动创建或复用：

```text
Ubuntu 22.04
CUDA Toolkit 13.0 / nvcc
Python 3.13
PyTorch 2.13.0+cu130（或指定的 2.14.0+cu130）
```

因此普通 Docker 构建不依赖宿主机的 Python、PyTorch 或 CUDA Toolkit。

### 服务器原生构建

如果服务器本身已经是 CUDA devel 环境，也可以不使用 Docker：

```bash
BUILD_BACKEND=native ./build-all.sh
```

这种方式要求服务器本身已有：

```text
Python、PyTorch、CUDA Toolkit、nvcc、gcc/g++、git
```

普通 ComfyUI 运行服务器不适合直接使用 native 构建方式。

### 自动选择

不指定 `BUILD_BACKEND` 时：

```bash
./build-all.sh
```

脚本会自动选择 Docker 或 native 后端。

## 使用 GitHub Actions 构建 Release

仓库包含 `.github/workflows/build-release.yml`。它会在 GitHub Actions 中
使用 Docker 构建并发布以下架构的 wheel：

```text
SM80  → A100/A800
SM86  → RTX 30xx
SM89  → RTX 40xx
SM120 → RTX 50xx
```

使用方法：

1. 将工作流合并到 `main`
2. 打开仓库的 `Actions`
3. 选择 `构建并发布 SageAttention Wheels`
4. 点击 `Run workflow`
5. 默认使用 Python 3.13、PyTorch 2.13.0、CUDA 13.0

工作流默认按顺序构建四种架构，并上传 `.whl`、`SHA256SUMS`，最后自动
创建 GitHub Release。构建机不需要显卡。

由于官方 PyTorch `devel` 镜像的默认 Python 版本不是固定的 3.13，工作流
基于 NVIDIA CUDA 13.0 / Ubuntu 22.04 镜像创建 Python 3.13 `venv`，再安装
匹配的 PyTorch。这样生成的 wheel 才会真正带有 `cp313` ABI，并以 Ubuntu
22.04 作为二进制兼容基线。

如果要跟随新的 ComfyUI release 使用 PyTorch 2.14.0，可以在工作流输入中
将 PyTorch 版本改为 `2.14.0`；builder 会在相同 CUDA 13.0 / Python 3.13
环境中安装 PyTorch 2.14.0。

## 构建默认版本

当前默认配置为 Python 3.13、PyTorch 2.13.0、CUDA 13.0：

```bash
SM_LIST="80 86 89 90 120" \
SAGE_REF="v2.2.0" \
TORCH_VER="2.13.0" \
CUDA_TAG="cu130" \
PY_TAG="cp313" \
BUILD_BACKEND="docker" \
MAX_JOBS="1" \
./build-all.sh
```

如果只需要 RTX 30xx 和 RTX 40xx：

```bash
SM_LIST="86 89" MAX_JOBS="1" ./build-all.sh
```

构建结果位于：

```text
./dist/
```

脚本还会生成：

```text
./dist/SHA256SUMS
```

`build-all.sh` 默认会先清理 `dist/` 中旧的 SageAttention wheel 和
`SHA256SUMS`，避免把不同 Python/PyTorch 版本的历史产物混入同一个 Release。

## PyTorch 2.14.0 构建配置

PyTorch 2.14.0 配置不会替换默认的 2.13.0 配置。需要跟随新的 ComfyUI
release 或运行环境时，可以使用：

```bash
SM_LIST="80 86 89 90 120" \
SAGE_REF="v2.2.0" \
TORCH_VER="2.14.0" \
CUDA_TAG="cu130" \
PY_TAG="cp313" \
BUILD_BACKEND="docker" \
MAX_JOBS="1" \
./build-all.sh
```

构建前可以单独创建并检查 builder：

```bash
TORCH_VER="2.14.0" ./prepare-builder.sh
```

脚本会输出 Python、PyTorch、Triton 和 `nvcc` 版本。构建脚本也会自动
检查 Python、PyTorch、CUDA 版本，发现不匹配会停止构建。

## 构建依赖

SageAttention v2.2.0 的构建阶段主要需要：

```text
Python >= 3.9
PyTorch >= 2.3.0
Triton >= 3.0.0
CUDA Toolkit / nvcc >= 12.0
C++17 编译器
packaging、setuptools、wheel
```

不同 GPU 架构还有更高的 CUDA 最低版本要求：

```text
SM80   CUDA >= 12.0
SM86   CUDA >= 12.0
SM89   CUDA >= 12.4
SM90   CUDA >= 12.3
SM120  CUDA >= 12.8
```

CUDA 13.0 可以覆盖当前项目的全部目标架构。

构建阶段每个并行任务可能需要较多内存。小内存机器建议：

```bash
MAX_JOBS=1
```

## 运行时安装

运行机器需要与构建 wheel 匹配：

```text
Python ABI
PyTorch 版本
PyTorch CUDA 构建版本
GPU SM 架构
```

例如当前 ComfyUI 环境是 Python 3.13、PyTorch 2.13.0+cu130，并且显卡是
RTX 3090，应安装 SM86 wheel：

```bash
python -m pip install --no-deps \
  sageattention-2.2.0-86-cp313-cp313-linux_x86_64.whl
```

RTX 4090 应安装 SM89 wheel：

```bash
python -m pip install --no-deps \
  sageattention-2.2.0-89-cp313-cp313-linux_x86_64.whl
```

运行阶段通常不需要：

```text
CUDA Toolkit
nvcc
SageAttention 源码
```

但运行时需要正确的 NVIDIA 驱动和对应 GPU。没有 GPU 时可以安装 wheel，
但无法完成真实 CUDA kernel 验证。

## ComfyUI 依赖

SageAttention 只负责 Attention 扩展，不替代 ComfyUI 自身依赖。ComfyUI
仍应在对应 release 的目录中执行：

```bash
pip install -r requirements.txt
```

`torchvision`、`torchaudio`、`torchsde`、`transformers`、`safetensors` 等
版本以对应 ComfyUI release 的 `requirements.txt` 为准，不要为了构建
SageAttention 而盲目升级整个环境。

## 许可证

本项目发布的 wheel 是重新打包的
[SageAttention](https://github.com/thu-ml/SageAttention) 二进制文件，遵循
Apache-2.0 许可证。本项目中的构建脚本同样遵循 Apache-2.0 许可证。
