# Android Kernel 增量编译指南

本文档介绍如何使用修改后的构建脚本进行增量编译，以显著减少重复编译的时间。

## 主要改进

修改后的构建系统具有以下特性：

1. **智能增量编译**: 默认启用增量编译，只重新编译发生变化的部分
2. **配置变更检测**: 自动检测配置文件变更，仅在需要时重新生成配置
3. **保留编译状态**: 保留之前的编译产物，避免不必要的重复编译
4. **快速重建**: 小幅代码修改后，编译时间从20-30分钟减少到2-5分钟

## 使用方法

### 1. 增量编译（推荐）

```bash
# 直接使用改进的构建脚本（默认增量编译）
build/build.sh

# 或者使用专门的增量编译脚本
build/incremental_build.sh
```

### 2. 强制完全重建

当你需要完全清理重建时：

```bash
# 方法1: 使用环境变量
FORCE_CLEAN=1 build/build.sh

# 方法2: 使用便捷脚本
build/incremental_build.sh --clean
```

### 3. 仅重新配置

当配置文件变更但不需要完全重建时：

```bash
# 方法1: 使用环境变量
SKIP_MRPROPER=1 build/build.sh

# 方法2: 使用便捷脚本
build/incremental_build.sh --config
```

## 关于 Image.lz4-dtb 文件生成

**是的，增量编译会重新生成 `out/android-msm-pixel-4.9/private/msm-google/arch/arm64/boot/Image.lz4-dtb` 文件。**

这个文件是最终的内核镜像文件，包含：
- 压缩的内核镜像 (Image.lz4)
- 设备树二进制文件 (DTB)

当你修改任何内核源代码时，增量编译会：
1. 只重新编译修改的源文件及其依赖
2. 重新链接内核
3. 重新生成压缩的内核镜像
4. 重新创建最终的 Image.lz4-dtb 文件

## 时间对比

| 编译类型 | 第一次编译 | 小幅修改后 | 配置变更后 |
|----------|------------|------------|------------|
| 原始脚本 | 20-30 分钟 | 20-30 分钟 | 20-30 分钟 |
| 增量编译 | 20-30 分钟 | 2-5 分钟   | 5-10 分钟  |

## 环境变量说明

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `INCREMENTAL_BUILD` | `1` | 启用增量编译 |
| `FORCE_CLEAN` | `0` | 强制完全重建 |
| `SKIP_MRPROPER` | 自动 | 跳过 mrproper 清理 |
| `SKIP_DEFCONFIG` | 自动 | 跳过 defconfig 重新生成 |

## 智能检测逻辑

增量编译系统会自动检测：

1. **首次编译**: 如果 `.config` 不存在，执行完全编译
2. **配置变更**: 如果 `defconfig` 或 `build.config*` 文件比 `.config` 新，重新生成配置
3. **代码变更**: 仅重新编译修改的源文件和依赖

## 故障排除

### 如果增量编译出现问题

```bash
# 强制完全重建
build/incremental_build.sh --clean
```

### 如果需要调试编译过程

```bash
# 启用详细输出
build/incremental_build.sh -j24 V=1
```

### 检查当前编译状态

```bash
# 查看 .config 文件时间戳
ls -la out/android-msm-pixel-4.9/.config

# 查看最新的内核镜像
ls -la out/android-msm-pixel-4.9/private/msm-google/arch/arm64/boot/Image.lz4-dtb
```

## 注意事项

1. **首次使用**: 第一次编译仍需要完整时间（20-30分钟）
2. **磁盘空间**: 增量编译会保留更多中间文件，需要额外磁盘空间
3. **配置变更**: 修改内核配置时建议使用 `--config` 选项
4. **清理**: 定期使用 `--clean` 选项进行完全重建以确保一致性

## 文件位置

- 增量编译脚本: `build/incremental_build.sh`
- 主构建脚本: `build/build.sh` (已修改支持增量编译)
- 配置文件: `private/msm-google/build.config.*`
- 输出目录: `out/android-msm-pixel-4.9/`
- 最终镜像: `out/android-msm-pixel-4.9/private/msm-google/arch/arm64/boot/Image.lz4-dtb`