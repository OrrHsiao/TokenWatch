//
//  TokenWatch-Bridging-Header.h
//  TokenWatch
//
//  将 App Target 内编译的 C 代码暴露给 Swift。
//  目前只用于内置的 zstd 解码器（见 TokenWatch/Vendor/Zstd/README.md）。
//  对应的 build setting 为 SWIFT_OBJC_BRIDGING_HEADER = TokenWatch/TokenWatch-Bridging-Header.h。
//

#import "Vendor/Zstd/zstd-decoder.h"
