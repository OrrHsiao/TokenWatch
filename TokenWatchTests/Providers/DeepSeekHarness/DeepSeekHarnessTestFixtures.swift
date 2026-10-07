import Foundation
@testable import TokenWatch

/// DeepSeek Harness provider 的测试夹具。
///
/// 压缩夹具由真实 v4 会话日志裁剪而来，并用 `zstd` 官方 CLI 按 DSH 的方式
/// **逐批次独立成帧**（一个 header 帧 + 每个追加批次一帧），用于验证多帧解码、
/// 世代去重、替换/重试折叠与 fork 继承前缀等关键路径。
enum DeepSeekHarnessTestFixtures {
    /// v4 多帧会话：
    /// - turn1/step1 两条样本（后者替换前者，最终 200/20/2000）
    /// - turn1/step2 失败尝试（0 用量）→ `llm/retry-started` → 成功样本 50/5/1000
    /// - turn2/step1 只有 `assistant/attempt`，用量在 stream 末尾 7/1/700
    /// - 一条未知类型事件、一条 `compaction/summary`（官方投影不计入）
    static let multiFrameV4Log = Data(base64Encoded: multiFrameV4LogBase64)!

    /// 已 fork 的子代理会话（`isSeeded: true`）：前两条事件属于继承前缀，必须跳过。
    static let seededForkLog = Data(base64Encoded: seededForkLogBase64)!

    /// v4 多帧夹具的折算基准（用于断言解析结果）。
    static let multiFrameV4Totals = (inputTokens: 257, outputTokens: 26, cacheReadTokens: 3_700, recordCount: 3)

    /// fork 夹具折算基准：只统计标记之后的样本。
    static let seededForkTotals = (inputTokens: 10, outputTokens: 2, cacheReadTokens: 100, recordCount: 1)

    private static let multiFrameV4LogBase64 =
        "KLUv/QBYDQQAMskdH2BVmwMDlK9yebtdom829QFjcAad1PhHtIACRZAl4AGBAKtTytQ+p/fvDrHsjzIuacW2H1i0Vj2HrsY/" +
        "SDlpvf6Jt4xeRK4pjbGK0/pojIkhpMSkQVoKSZBeg37VXWO0Su4aC1lOosvIpLvDaBat9/6cfousAQICAD63aFuaKLUv/QBY" +
        "fQgAJpAwH3BJqgMmGYkI0b0tM+Q/JEfQVAD4DgC7+SOfpR/WfQEmACkAJQD6t2optOee6FEj9SylGP0iq59Fn7D8PGur0x7L" +
        "h2NVQ65ft9BPAnr2YB+zCMS8yKEZal7MyBDjE4wOhMIACCgUxi67XXV9viGKVS2xde0B7clsjVbQ0LH1ROEzr9gynug3Pdj4" +
        "eVMgGLlereeP9p6o2+anCYYYYynlnHNOwDmIUQduMJhIBnoE7Wt+xlKKQkuwiYTSsxhzoG79bBgdAIBGMDPgyQvQA4JR3ccN" +
        "phgZixExA44qd3MCwk3cUrCsUuss6qjC2Jx2Qqds344q7WDh9rornNqKAJbrwWFARDrIUo4yHmUIUSi1L/0AWF0IABYRNCJA" +
        "qaYNXesgy2VG25oZVlHBAgjBY7AeRJTwenb4kzFsHWMCKQArACcAZ5VoZ2TyCJ+dzG9ZFgm8Pql/CbyCrt97VaKHnahtlinK" +
        "rBnkeIUW+lEJuRgeg8F4syzyOMA/qdzrB4CHtNcPgV9mvSgU0KPdqfRmr7RWGlpTxo0BkN9ZMevxzKbmEX7VSuXfIyttglxr" +
        "zclW3Uz9FvxabZSjGbTpEd41htYQ+DuCj2cEFgtGm7PXYYFbWXkcB6G11u5oEBQYDAQ0HMcrox6P8MrMSRkWAEQFoLTynroA" +
        "nAOEBQIMO4sLQEGzAeiQAAqaEFVoNGVbcXaUvjeZNL6Ur1AMwBsQoYmyDVQEMyi1L/0AWIULAGaWQSJAbdoG+KxjsnZMWkMn" +
        "4EhXfms3FtyOgsQMNF7nd8awMSYHNAA5ADkA7Hm1jleYeSSPi/yy7Y5JvjFNP5LXVnU85xDkl60+EuQb1h2/DnVumaKbtlvO" +
        "6fO7RPQjAQvhhG6Wth7J5vjeH04VhkQSMOCQgOy6ZVc98exIrOLUduHnmVXLgZnleGUVtwV5JL+Jadgdv0g4XG+IbXzvndNI" +
        "GokOac0jKeSZLrNoNHph260A7z0BR1uNnS5zPEfpIuwjaToyGCdRtLmP3fDxMPKuBQDvXekyzy/ThpCiaFIozI0QQgghxMh3" +
        "a9hgH1jpwx2fpOfVQUFBBKOMNU7ReHXShXFaeO/r8cQqIJAioSK7ARyBXGSJA85BUIxQCYGAGzo84/DSNvjcEMaICCtBeBQD" +
        "HK2Og+kug7VmYyVnD8J3AnsPx1G5e8Jw7baU67IfL0yciUlEhLExaUM+9a5FxF7ntm1tTORyfCFfPnDZRI4C"

    private static let seededForkLogBase64 =
        "KLUv/QBY5QQAwsohIGBLmwPDMrGl3G7EIjWd6gl2g3Pc0scsV+/QgyTILcgDiQinolRom9H7di3wJWiEZSdQKy1irvD0edUZ" +
        "pBKTdPne6KLz+S9a8hktVl0R8zlhKTvYwh5GZ8PiUxwBBVFOwEEUJ0HvQH7RdfF5Ma7NOqQDw6BpRmfyAaCewWe1UmtvRp89" +
        "rCECBgD8CCePYyYspmIJBsRptC1iKLUv/QBYdQcA0s8sHnA31QFGQ0FWqKXFYGtfk/Glnf46peD2j3yWftzFAYQYYymmLANm" +
        "OIfuqY9J/xppvbCY2v0SYoyGhC5w5ECH85xzzoPMadS7jmADD7alnCh0xmhkUYLAMAABCwPxb/uTNc0OxhM71huz2j2pBXPN" +
        "6cQTU1idlkI4Uf9wkK3Txkh/yh1ZyuqknE4w50Tb3zqNejn4nKjRQ8lZilFfoZ6zqAu+Tv+Adq8ovIXeql1k9dvBcxIVAFmb" +
        "QNfOd4WtdAzkAcFnu1gmeKFNAYAfEKZjCfBYlbjLREVATnvxA+9MwwdRN1rhlFYEBa9iBg=="
}
