/*
 * TokenWatch 使用的 zstd 解码 API 子集声明。
 *
 * 背景：macOS SDK 的 Compression/Foundation 均不提供 zstd，系统也不存在 libzstd，
 * 因此 zstddeclib.c（zstd 官方单文件解码器，BSD-3-Clause）被直接编译进 App Target。
 * 该单文件已内含完整实现，但 Swift 无法直接看到其中的声明，故此处抄录官方
 * `lib/zstd.h` 中本模块实际使用的最小 ABI 子集，供 bridging header 引入。
 *
 * 稳定性依据：`ZSTD_inBuffer` / `ZSTD_outBuffer` 的字段布局与
 * `ZSTD_createDStream` / `ZSTD_decompressStream` 等函数签名自 zstd v1.3.0 起为
 * 稳定公开 ABI（见 zstd 官方 `lib/zstd.h` 的 "Streaming" 段落），
 * 因此升级 zstddeclib.c 时无需同步修改本文件，除非要用到新的 API。
 */
#ifndef TOKENWATCH_ZSTD_DECODER_H
#define TOKENWATCH_ZSTD_DECODER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ZSTD_DCtx 与 ZSTD_DStream 自 v1.3.0 起为同一对象。 */
typedef struct ZSTD_DCtx_s ZSTD_DCtx;
typedef ZSTD_DCtx ZSTD_DStream;

typedef struct ZSTD_inBuffer_s {
    const void *src; /* 输入起始地址 */
    size_t size;     /* 输入长度 */
    size_t pos;      /* 已消费位置，由解码器更新 */
} ZSTD_inBuffer;

typedef struct ZSTD_outBuffer_s {
    void *dst;   /* 输出起始地址 */
    size_t size; /* 输出容量 */
    size_t pos;  /* 已写入长度，由解码器更新 */
} ZSTD_outBuffer;

ZSTD_DStream *ZSTD_createDStream(void);
size_t ZSTD_freeDStream(ZSTD_DStream *zds);
size_t ZSTD_initDStream(ZSTD_DStream *zds);

/* 返回 0 表示当前帧已完整解码并输出；>0 表示仍需继续；错误用 ZSTD_isError 判定。 */
size_t ZSTD_decompressStream(
    ZSTD_DStream *zds,
    ZSTD_outBuffer *output,
    ZSTD_inBuffer *input
);

unsigned ZSTD_isError(size_t result);
const char *ZSTD_getErrorName(size_t result);

#ifdef __cplusplus
}
#endif

#endif /* TOKENWATCH_ZSTD_DECODER_H */
