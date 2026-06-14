import Foundation
import Testing
@testable import TokenWatch

/// JSONLScanner 测试
/// 重点覆盖 `decodeProjectPath` 对编码后项目目录名的还原逻辑,
/// 包含含有字面 `-` 的项目名(经验性 `--` 转义假设)。
struct JSONLScannerTests {

    let scanner = JSONLScanner()

    // MARK: - decodeProjectPath

    @Test("解码常规绝对路径 - 单 `-` 还原为 `/`")
    func decodePlainAbsolutePath() {
        let decoded = scanner.decodeProjectPath("-Users-name-project")
        #expect(decoded == "/Users/name/project")
    }

    @Test("解码含连字符项目名 - `--` 还原为字面 `-`")
    func decodePathWithHyphenInProjectName() {
        // my-cool-app 在编码时变成 my--cool--app,解码后需还原为 my-cool-app
        let decoded = scanner.decodeProjectPath("-Users-name-my--cool--app")
        #expect(decoded == "/Users/name/my-cool-app")
    }

    @Test("解码混合场景 - 普通段与含连字符段共存")
    func decodeMixedPath() {
        // /Users/orr/some-repo/sub  ->  -Users-orr-some--repo-sub
        let decoded = scanner.decodeProjectPath("-Users-orr-some--repo-sub")
        #expect(decoded == "/Users/orr/some-repo/sub")
    }

    @Test("解码连续多个字面 `-` - `----` 还原为 `--`")
    func decodeDoubleHyphenLiteral() {
        // 项目名 a--b 编码时变成 a----b(每个 `-` 转义为 `--`)
        let decoded = scanner.decodeProjectPath("-tmp-a----b")
        #expect(decoded == "/tmp/a--b")
    }

    // MARK: - 边界条件

    @Test("空字符串原样返回")
    func decodeEmptyString() {
        #expect(scanner.decodeProjectPath("") == "")
    }

    @Test("单个 `-` 还原为根目录 `/`")
    func decodeSingleHyphen() {
        // 仅 "-" 表示原始路径就是 "/"(只有起始斜杠,无后续内容)
        #expect(scanner.decodeProjectPath("-") == "/")
    }

    @Test("首字符非 `-` 时原样返回(非 Claude 编码格式)")
    func decodeNonEncodedString() {
        // 不以 `-` 开头说明不是 Claude Code 编码格式,直接原样返回避免误处理
        #expect(scanner.decodeProjectPath("Users/name/project") == "Users/name/project")
        #expect(scanner.decodeProjectPath("plain-string") == "plain-string")
    }

    @Test("末尾以单 `-` 结尾 - 还原为以 `/` 结尾")
    func decodeTrailingSingleHyphen() {
        // 边界:虽然实际编码不会出现,但解析器应稳健处理
        let decoded = scanner.decodeProjectPath("-Users-name-")
        #expect(decoded == "/Users/name/")
    }

    @Test("末尾以 `--` 结尾 - 还原为以 `-` 结尾")
    func decodeTrailingDoubleHyphen() {
        let decoded = scanner.decodeProjectPath("-tmp-foo--")
        #expect(decoded == "/tmp/foo-")
    }
}
