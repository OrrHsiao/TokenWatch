# Vendored: zstd 官方单文件解码器

## 为什么需要它

DeepSeek Harness 的会话日志（`~/.dsh/sessions/**/session.vN.jsonl.zstd`）默认使用
**多帧拼接的 zstd** 编码，而 macOS 既不提供 `libzstd`，`Compression` / `Foundation`
也不支持 zstd（SDK 27 的 `compression.h` 无该算法，`/usr/lib/libzstd*.dylib` 不存在）。
因此本项目直接内置 zstd 的解码实现（只含解码器，不含压缩器）。

## 文件来源

| 文件 | 来源 |
|---|---|
| `zstddeclib.c` | zstd v1.5.7 官方 `build/single_file_libs/zstddeclib.c`（由 `create_single_file_decoder.sh` 用 `combine.py` 生成） |
| `zstd-decoder.h` | 本项目手写；抄录 `lib/zstd.h` 中实际使用的最小 ABI 子集 |
| `LICENSE` | zstd 官方 BSD-3-Clause 许可证原文 |

- 上游仓库：https://github.com/facebook/zstd
- 版本：v1.5.7（`zstd-1.5.7.tar.gz`）
- 生成命令：
  ```sh
  curl -sSL -o zstd.tar.gz https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz
  tar xzf zstd.tar.gz && cd zstd-1.5.7/build/single_file_libs
  ./create_single_file_decoder.sh   # 产出 zstddeclib.c
  ```
- 内容校验（SHA-256）：`5eb38abe0a7eea13674b312a006df72002d4192f0f0b4d09e6f03fb927a1f3d0`

## 许可证

zstd 采用 **BSD-3-Clause**（见同目录 `LICENSE`），与 App Store 分发兼容；
`zstddeclib.c` 文件头亦声明 “BSD-style license (found in the LICENSE file in the root
directory of this source tree) and the GPLv2 … You may select, at your option, one of
the above-listed licenses.”，本项目按 BSD-3-Clause 使用。

## 使用方式

- `zstddeclib.c` 由 Xcode 的 file-system synchronized group 自动加入 App Target 编译；
- `zstd-decoder.h` 通过根目录 `TokenWatch-Bridging-Header.h` 暴露给 Swift；
- Swift 侧封装见 `TokenWatch/Providers/DeepSeekHarness/DeepSeekHarnessZstdDecoder.swift`。

由于 DSH 日志是**多帧拼接流**，一次性 `ZSTD_decompress()` 只能得到第一帧（即 header 行），
必须使用流式 API `ZSTD_decompressStream` 循环解帧。
