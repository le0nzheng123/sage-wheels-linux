# 项目变更记录

## 2026-09-21：跟随 ComfyUI Release 的构建流水线

本次调整用于让 SageAttention wheel 与 ComfyUI 使用的 Python、PyTorch 和
CUDA 组合保持一致。当前默认目标为：

```text
SageAttention 2.2.0
Python 3.13
PyTorch 2.13.0+cu130
CUDA Toolkit 13.0
Linux
```

### 支持的 GPU 架构

| SM | GPU 示例 | 默认 GitHub Release |
|---:|---|---|
| 80 | A100/A800 | 包含 |
| 86 | RTX 3060/3080/3090、A10/A40 | 包含 |
| 89 | RTX 4090、L40/L40S | 包含 |
| 90 | H100/H200 | 脚本支持，默认 Release 不构建 |
| 120 | RTX 50xx、B200 | 包含 |
| 75 | RTX 20xx、T4 | SageAttention 2.2.0 暂不支持 |

### 构建环境调整

- 使用 `nvidia/cuda:13.0.0-devel-ubuntu22.04` 作为构建基线。
- 在 builder 中创建 Python 3.13 `venv`。
- 安装对应的 PyTorch `cu130` wheel 和 Triton。
- 不再依赖 Conda。
- 构建阶段需要 CUDA Toolkit 和 `nvcc`；安装预编译 wheel 的 ComfyUI
  运行环境通常不需要 `nvcc`。
- 新增 `prepare-builder.sh`，Docker 模式会自动创建或复用 builder。
- 同时保留 `BUILD_BACKEND=docker` 和 `BUILD_BACKEND=native`。

### GitHub Actions 调整

- 默认从 `main` 手动触发 Release workflow。
- 默认构建 SM80、SM86、SM89、SM120 四个 wheel。
- PyTorch 版本提供 `2.13.0` 和 `2.14.0` 选项。
- 对 SageAttention ref、SM 列表、并行任务数和 Release tag 进行输入校验。
- 构建前后显示磁盘使用情况，方便诊断 GitHub runner 空间问题。
- 校验 wheel 数量、文件名、二进制扩展、SHA256、动态依赖和 Python import。
- Release 已存在时停止发布，不覆盖历史 Release。
- 新增 PR 静态检查：Bash 语法、ShellCheck、Dockerfile 检查。

### 已修复问题

- 修复 PyTorch 官方 devel 镜像实际为 Python 3.12、却尝试生成 `cp313`
  wheel 的问题。
- 修复构建镜像中没有 `conda` 导致的 `conda: not found`。
- 修复普通 Docker 构建与 GitHub Actions 使用不同 Python 环境的问题。
- 修复 Actions 输入直接拼接到 Shell 脚本的风险。
- 修复不同构建版本的旧 wheel 可能混入同一 Release 的问题。
- 移除 apt、git fetch 等关键操作中的静默失败处理。
- 统一使用 `python -m pip`，避免 `python` 与 `pip` 指向不同环境。
- 修复 Release 阶段使用 `sed -n` 却未输出匹配结果，导致成功构建的 wheel
  无法创建 GitHub Release。
- 更新 artifact 上传和下载 actions，避免旧 Node.js runtime 弃用警告。
- PyTorch 2.14.0 构建时自动为 C++ 和 NVCC 追加 C++20 标准参数；
  PyTorch 2.13.0 继续使用 SageAttention 2.2.0 原有的 C++17 配置。

### 使用方法

GitHub Actions：

```text
Actions
→ 构建并发布 SageAttention Wheels
→ Run workflow
→ Select ref: main
```

默认输入：

```text
torch_version = 2.13.0
sage_ref      = v2.2.0
sm_list       = 80 86 89 120
max_jobs      = 1
release_tag   = 留空
```

本地 Docker 构建：

```bash
BUILD_BACKEND=docker MAX_JOBS=1 ./build-all.sh
```

服务器原生构建：

```bash
BUILD_BACKEND=native MAX_JOBS=1 ./build-all.sh
```

### 验证边界

GitHub Actions 的普通 runner 没有 NVIDIA GPU，因此可以完成 CUDA 编译、
wheel 导入和静态检查，但不能代替真实 GPU kernel 运行测试。发布后仍建议在
对应 GPU 上进行一次 ComfyUI 实际工作流验证。
