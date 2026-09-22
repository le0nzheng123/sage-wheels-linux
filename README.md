# SageAttention Linux Wheels

为 ComfyUI 构建 SageAttention 2.2.0 Linux 预编译 wheel。

构建阶段需要 CUDA Toolkit 和 `nvcc`；安装已经编译好的 wheel 时通常不需要
`nvcc`。

- [SageAttention 上游项目](https://github.com/thu-ml/SageAttention)
- [Releases](https://github.com/le0nzheng123/sage-wheels-linux/releases)
- [构建说明](./BUILD.md)
- [变更记录](./CHANGE.md)

## 默认构建配置

```text
SageAttention  2.2.0
Python         3.13
PyTorch        2.13.0+cu130
CUDA Toolkit   13.0
系统基线        Ubuntu 22.04 / Linux
```

| SM | GPU 示例 | 默认 Release |
|---:|---|---|
| 80 | A100/A800 | 包含 |
| 86 | RTX 30xx、A10/A40 | 包含 |
| 89 | RTX 40xx、L40/L40S | 包含 |
| 90 | H100/H200 | 脚本支持，默认不构建 |
| 120 | RTX 50xx、B200 | 包含 |
| 75 | RTX 20xx、T4 | SageAttention 2.2.0 暂不支持 |

SageAttention 是 Attention 后端，不负责 ComfyUI 多卡调度。

## GitHub Actions 构建 Release

打开仓库的 `Actions`，选择 `构建并发布 SageAttention Wheels`：

```text
Select ref   main
PyTorch     2.13.0
Sage ref    v2.2.0
SM list     80 86 89 120
MAX_JOBS    1
Release tag 留空自动生成
```

工作流会依次完成：

```text
准备 Python 3.13 / CUDA 13.0 builder
→ 编译四个 SM wheel
→ 校验 SHA256、动态依赖和 Python import
→ 上传 artifact
→ 创建 GitHub Release
```

GitHub runner 没有 NVIDIA GPU，因此可以完成编译和静态验证，但最终仍建议在
对应 GPU 上运行一次 ComfyUI 工作流。

### Linux Multi-SM Wheel

仓库另外提供 `构建并发布 SageAttention Linux Multi-SM Wheel` 工作流。它不修改
原有单 SM 构建流程，默认把以下架构编译进同一个 wheel：

```text
SM80  A100/A800
SM86  RTX 30xx
SM89  RTX 40xx
```

RTX 50xx（SM120）默认不构建，但仍可在运行工作流时把 `SM list` 改成
`80 86 89 120`。本地 Docker 构建命令：

```bash
SM_LIST="80 86 89" BUILD_BACKEND=docker MAX_JOBS=1 ./build-multi-sm.sh
```

产物位于 `dist-multi-sm/`，与原有 `dist/` 完全分开。

## Wheel 文件名

格式：

```text
sageattention-<版本>-<SM>-<Python tag>-<ABI tag>-<平台>.whl
```

例如：

```text
sageattention-2.2.0-120-cp313-cp313-linux_x86_64.whl
```

| 字段 | 含义 |
|---|---|
| `2.2.0` | SageAttention 版本 |
| `120` | SM120 / RTX 50xx、B200 |
| 第一个 `cp313` | Python tag：CPython 3.13 |
| 第二个 `cp313` | ABI tag：CPython 3.13 ABI |
| `linux_x86_64` | Linux x86_64 平台 |

`cp313-cp313` 是标准 Wheel 命名，不是重复错误。

Release tag 格式：

```text
sage-<Sage版本>-torch-<PyTorch版本>-<CUDA>-py<Python版本>
```

例如：

```text
sage-2.2.0-torch-2.13.0-cu130-py313
```

## 本地或服务器构建

Docker 构建，不需要宿主机安装 CUDA Toolkit：

```bash
BUILD_BACKEND=docker MAX_JOBS=1 ./build-all.sh
```

脚本会自动创建或复用 Python 3.13 builder。

原生构建要求服务器已经安装匹配的 Python、PyTorch、CUDA Toolkit、`nvcc`
和 C++ 编译器：

```bash
BUILD_BACKEND=native MAX_JOBS=1 ./build-all.sh
```

只构建部分架构：

```bash
SM_LIST="86 89" MAX_JOBS=1 ./build-all.sh
```

产物位于：

```text
dist/
├── sageattention-*.whl
└── SHA256SUMS
```

PyTorch 2.14.0 可通过以下方式构建：

```bash
TORCH_VER="2.14.0" BUILD_BACKEND=docker MAX_JOBS=1 ./build-all.sh
```

## 安装

wheel 必须匹配 Python、PyTorch/CUDA 和 GPU SM 架构。

例如 RTX 30xx 使用 SM86：

```bash
python -m pip install --no-deps \
  sageattention-2.2.0-86-cp313-cp313-linux_x86_64.whl
```

RTX 40xx 使用 SM89：

```bash
python -m pip install --no-deps \
  sageattention-2.2.0-89-cp313-cp313-linux_x86_64.whl
```

验证：

```bash
python -c "import sageattention; print(sageattention.__file__)"
```

ComfyUI 自身依赖仍以对应 release 的 `requirements.txt` 为准。

## 许可证与致谢

SageAttention 上游代码遵循 Apache-2.0 许可证，本项目构建脚本同样遵循
Apache-2.0 许可证。

感谢 **Codex** 与 **OpenAI** 在代码审查、构建流水线调试和文档整理中的协助。
