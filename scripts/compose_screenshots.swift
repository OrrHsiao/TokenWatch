#!/usr/bin/env swift

import Foundation
import AppKit

// MARK: - Models

struct Manifest: Codable {
    let version: Int
    let canvas: CanvasConfig
    let locales: [String]
    let screens: [ScreenConfig]
}

struct CanvasConfig: Codable {
    let width: Int
    let height: Int
    let colorSpace: String
    let alpha: Bool
}

struct ScreenConfig: Codable {
    let id: String
    let type: String
    let titles: [String: LocalizedTitle]
}

struct LocalizedTitle: Codable {
    let title: String
    let subtitle: String
}

// MARK: - Screenshot Compositor

final class ScreenshotCompositor {
    let rootDir: URL
    let manifest: Manifest

    init(rootDir: URL) throws {
        self.rootDir = rootDir
        let manifestURL = rootDir.appendingPathComponent("snapshots/manifest.json")
        let data = try Data(contentsOf: manifestURL)
        self.manifest = try JSONDecoder().decode(Manifest.self, from: data)
    }

    func composeAll() throws {
        let canvasWidth = manifest.canvas.width
        let canvasHeight = manifest.canvas.height

        print("🚀 开始自动装裱 App Store 截图...")
        print("📐 画布尺寸: \(canvasWidth)x\(canvasHeight), sRGB, 无 Alpha 通道")

        for locale in manifest.locales {
            let outputDir = rootDir.appendingPathComponent("snapshots/appstore_snapshot/\(locale)")
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

            for screen in manifest.screens {
                guard let localizedTitle = screen.titles[locale] else {
                    print("⚠️ 缺少 \(locale) 的文案配置: \(screen.id)")
                    continue
                }

                let outputFile = outputDir.appendingPathComponent("\(screen.id).png")
                try composeScreen(
                    screen: screen,
                    locale: locale,
                    title: localizedTitle.title,
                    subtitle: localizedTitle.subtitle,
                    outputURL: outputFile
                )
            }
        }

        print("\n✨ 所有 App Store 商店截图装裱完成！")
    }

    private func composeScreen(
        screen: ScreenConfig,
        locale: String,
        title: String,
        subtitle: String,
        outputURL: URL
    ) throws {
        let width = manifest.canvas.width
        let height = manifest.canvas.height

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw CompositorError.cannotCreateContext
        }

        // 1. 绘制暗色渐变背景（与现有 TokenWatch 品牌色相符）
        let topColor = CGColor(srgbRed: 9 / 255.0, green: 12 / 255.0, blue: 18 / 255.0, alpha: 1.0)
        let bottomColor = CGColor(srgbRed: 28 / 255.0, green: 35 / 255.0, blue: 43 / 255.0, alpha: 1.0)
        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [bottomColor, topColor] as CFArray,
            locations: [0.0, 1.0]
        )!
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: width / 2, y: 0),
            end: CGPoint(x: width / 2, y: height),
            options: []
        )

        // 2. 绘制顶部大标题与副标题
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext

        let titleStyle = NSMutableParagraphStyle()
        titleStyle.alignment = .center
        let titleFont = NSFont.systemFont(ofSize: 72, weight: .bold)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.99, alpha: 1.0),
            .paragraphStyle: titleStyle
        ]
        let titleRect = NSRect(x: 120, y: height - 125 - 82, width: width - 240, height: 90)
        (title as NSString).draw(in: titleRect, withAttributes: titleAttrs)

        let subtitleStyle = NSMutableParagraphStyle()
        subtitleStyle.alignment = .center
        let subtitleFont = NSFont.systemFont(ofSize: 34, weight: .regular)
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: NSColor(calibratedRed: 0.62, green: 0.64, blue: 0.68, alpha: 1.0),
            .paragraphStyle: subtitleStyle
        ]
        let subtitleRect = NSRect(x: 120, y: height - 245 - 46, width: width - 240, height: 50)
        (subtitle as NSString).draw(in: subtitleRect, withAttributes: subtitleAttrs)

        NSGraphicsContext.restoreGraphicsState()

        // 3. 根据页面类型绘制内容（窗口 或 状态栏悬浮窗）
        if screen.type == "window" {
            try renderWindowContent(screenID: screen.id, locale: locale, in: context, canvasWidth: width, canvasHeight: height)
        } else if screen.type == "popover" {
            try renderPopoverContent(locale: locale, in: context, canvasWidth: width, canvasHeight: height)
        }

        // 4. 保存为无 Alpha 通道的 24-bit PNG
        guard let outputCGImage = context.makeImage() else {
            throw CompositorError.cannotExportImage
        }
        let rep = NSBitmapImageRep(cgImage: outputCGImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw CompositorError.cannotEncodePNG
        }
        try pngData.write(to: outputURL, options: .atomic)
        print("  ✓ [\(locale)] 已生成 \(outputURL.lastPathComponent)")
    }

    private func renderWindowContent(
        screenID: String,
        locale: String,
        in context: CGContext,
        canvasWidth: Int,
        canvasHeight: Int
    ) throws {
        guard let rawImage = findRawImage(for: screenID, locale: locale) else {
            print("⚠️ 未找到 \(locale)/\(screenID) 的原图")
            return
        }

        let targetWidth: CGFloat = 2160
        let targetX: CGFloat = 360
        let scale = targetWidth / CGFloat(rawImage.pixelsWide)
        let targetHeight = CGFloat(rawImage.pixelsHigh) * scale
        let targetY = CGFloat(canvasHeight) - 390 - targetHeight
        let windowRect = CGRect(x: targetX, y: targetY, width: targetWidth, height: targetHeight)
        let cornerRadius: CGFloat = 16

        guard let cgImage = rawImage.cgImage else { return }

        // 绘制柔和窗口阴影
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -18),
            blur: 42,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5)
        )
        let path = CGPath(
            roundedRect: windowRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        context.addPath(path)
        context.fillPath()
        context.restoreGState()

        // 裁剪圆角并绘制窗口截图
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.draw(cgImage, in: windowRect)
        context.restoreGState()
    }

    private var didExportPopoverSnapshots = false

    private func renderPopoverContent(
        locale: String,
        in context: CGContext,
        canvasWidth: Int,
        canvasHeight: Int
    ) throws {
        let sbHeight: CGFloat = 60
        let sbY = CGFloat(canvasHeight) - 450 - sbHeight

        // 1. 绘制状态栏背景 (2880 全宽纯黑 macOS 原生状态栏底色)
        let fullSBRect = CGRect(x: 0, y: sbY, width: CGFloat(canvasWidth), height: sbHeight)
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1.0))
        context.fill(fullSBRect)

        guard let popoverRep = findPopoverImage(locale: locale),
              let popoverCGImage = popoverRep.cgImage else {
            print("⚠️ 未找到 \(locale) 的 popover 原图")
            return
        }

        let popWidth = CGFloat(popoverRep.pixelsWide)
        let popHeight = CGFloat(popoverRep.pixelsHigh)
        let popX = (CGFloat(canvasWidth) - popWidth) / 2
        let popY = CGFloat(canvasHeight) - 510 - popHeight
        let popRect = CGRect(x: popX, y: popY, width: popWidth, height: popHeight)

        let statusBarFile = rootDir.appendingPathComponent("snapshots/status_bar.png")
        if let sbData = try? Data(contentsOf: statusBarFile),
           let sbRep = NSBitmapImageRep(data: sbData),
           let sbCGImage = sbRep.cgImage {

            // 2. 左侧：macOS 经典苹果图标 (从 status_bar.png 提取 x: 35..85)
            if let appleCrop = sbCGImage.cropping(to: CGRect(x: 35, y: 0, width: 50, height: 60)) {
                let appleRect = CGRect(x: 40, y: sbY, width: 50, height: sbHeight)
                context.draw(appleCrop, in: appleRect)
            }

            // 3. 右侧：系统常驻控制图标 (Wi-Fi、控制中心、时间等，从 status_bar.png 提取 x: 3290..3810)
            let sysWidth: CGFloat = 520
            if let sysCrop = sbCGImage.cropping(to: CGRect(x: 3290, y: 0, width: Int(sysWidth), height: 60)) {
                let sysX = CGFloat(canvasWidth) - sysWidth - 40
                let sysRect = CGRect(x: sysX, y: sbY, width: sysWidth, height: sbHeight)
                context.draw(sysCrop, in: sysRect)
            }

            // 4. 正对 Popover 视图上方：TokenWatch 状态栏项目 (仪表盘图标 + 342.0k Tokens，原汁原味原生样式，无多余底色)
            let tokenWidth: CGFloat = 116
            let tokenX = popRect.midX - tokenWidth / 2

            NSGraphicsContext.saveGraphicsState()
            let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.current = nsContext

            // 绘制仪表盘 SF Symbol (以白色调色板渲染，保证在深色状态栏上清晰可见)
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            if let sym = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let iconRect = NSRect(x: tokenX, y: sbY + (sbHeight - 34) / 2, width: 34, height: 34)
                sym.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }

            // 绘制两行文本 (342.0k / Tokens)
            let primaryParagraph = NSMutableParagraphStyle()
            primaryParagraph.alignment = .left
            primaryParagraph.maximumLineHeight = 18
            primaryParagraph.minimumLineHeight = 18

            let secondaryParagraph = NSMutableParagraphStyle()
            secondaryParagraph.alignment = .left
            secondaryParagraph.maximumLineHeight = 14
            secondaryParagraph.minimumLineHeight = 14

            let attrStr = NSMutableAttributedString(
                string: "342.0k\n",
                attributes: [
                    .font: NSFont.boldSystemFont(ofSize: 18),
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: primaryParagraph
                ]
            )
            attrStr.append(NSAttributedString(
                string: "Tokens",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14),
                    .foregroundColor: NSColor(white: 0.9, alpha: 1.0),
                    .paragraphStyle: secondaryParagraph
                ]
            ))

            let textRect = NSRect(x: tokenX + 44, y: sbY + (sbHeight - 32) / 2 - 2, width: 72, height: 36)
            attrStr.draw(in: textRect)

            NSGraphicsContext.restoreGraphicsState()
        }

        // 5. 绘制弹出视图 (Popover) 柔和投影与圆角内容
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -14),
            blur: 36,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45)
        )
        let path = CGPath(
            roundedRect: popRect,
            cornerWidth: 12,
            cornerHeight: 12,
            transform: nil
        )
        context.addPath(path)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.clip()
        context.draw(popoverCGImage, in: popRect)
        context.restoreGState()
    }

    private func findRawImage(for screenID: String, locale: String) -> NSBitmapImageRep? {
        let rawDir = rootDir.appendingPathComponent("snapshots/raw/\(locale)")
        let rawURL = rawDir.appendingPathComponent("\(screenID).png")
        if let data = try? Data(contentsOf: rawURL), let rep = NSBitmapImageRep(data: data) {
            return rep
        }

        // 检查 UI 测试 Runner 容器内生成的最新原图并自动同步
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let runnerTmpURL = homeDir
            .appendingPathComponent("Library/Containers/com.xiaoao.TokenWatchUITests.xctrunner/Data/tmp/tokenwatch_screenshots/raw/\(locale)/\(screenID).png")
        if let data = try? Data(contentsOf: runnerTmpURL), let rep = NSBitmapImageRep(data: data) {
            try? FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true)
            try? data.write(to: rawURL)
            return rep
        }

        // 回退查找旧版/预置的原图命名
        let langSuffix = (locale == "zh-Hans") ? "zh" : "en"
        let fallbackCandidates: [String]
        switch screenID {
        case "02-overview":
            fallbackCandidates = ["overview-\(langSuffix).png", "overview_\(langSuffix).png"]
        case "03-sessions":
            fallbackCandidates = ["sessions-\(langSuffix).png", "sessions_\(langSuffix).png"]
        case "04-widgets":
            fallbackCandidates = ["widgets_\(langSuffix).png", "widgets-\(langSuffix).png"]
        default:
            fallbackCandidates = []
        }

        for candidate in fallbackCandidates {
            let candidateURL = rootDir.appendingPathComponent("snapshots/\(candidate)")
            if let data = try? Data(contentsOf: candidateURL), let rep = NSBitmapImageRep(data: data) {
                return rep
            }
        }

        return nil
    }

    private func findPopoverImage(locale: String) -> NSBitmapImageRep? {
        if !didExportPopoverSnapshots {
            _ = exportPopoverSnapshotsFromBinary()
            didExportPopoverSnapshots = true
        }

        let rawURL = rootDir.appendingPathComponent("snapshots/raw/\(locale)/01-menu-bar-popover.png")
        if let data = try? Data(contentsOf: rawURL), let rep = NSBitmapImageRep(data: data) {
            return rep
        }

        let langSuffix = (locale == "zh-Hans") ? "zh" : "en"
        let fallbackURL = rootDir.appendingPathComponent("snapshots/status_popview-\(langSuffix).png")
        if let data = try? Data(contentsOf: fallbackURL), let rep = NSBitmapImageRep(data: data) {
            return rep
        }

        return nil
    }

    private func exportPopoverSnapshotsFromBinary() -> Bool {
        let candidatePaths = [
            rootDir.appendingPathComponent(".build/DerivedData/Build/Products/Debug/AI Token Watch.app/Contents/MacOS/AI Token Watch"),
            rootDir.appendingPathComponent("build/Debug/AI Token Watch.app/Contents/MacOS/AI Token Watch")
        ]
        guard let binaryURL = candidatePaths.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return false
        }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["--export-popover-snapshots"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8) else {
                return false
            }

            let lines = output.components(separatedBy: .newlines)
            var currentLocale: String?
            var base64Lines: [String] = []

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("TOKENWATCH_SNAPSHOT_START:") {
                    currentLocale = String(trimmed.dropFirst("TOKENWATCH_SNAPSHOT_START:".count))
                    base64Lines.removeAll()
                } else if trimmed.hasPrefix("TOKENWATCH_SNAPSHOT_END:") {
                    if let locale = currentLocale,
                       let pngData = Data(base64Encoded: base64Lines.joined()) {
                        let targetDir = rootDir.appendingPathComponent("snapshots/raw/\(locale)")
                        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
                        let fileURL = targetDir.appendingPathComponent("01-menu-bar-popover.png")
                        try? pngData.write(to: fileURL)
                        print("  ✓ 自动从 App 二进制生成了 \(locale) 的 01-menu-bar-popover.png")
                    }
                    currentLocale = nil
                } else if currentLocale != nil {
                    base64Lines.append(trimmed)
                }
            }
            return true
        } catch {
            return false
        }
    }
}

enum CompositorError: Error {
    case cannotCreateContext
    case cannotExportImage
    case cannotEncodePNG
}

// MARK: - Main Execution

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()

do {
    let compositor = try ScreenshotCompositor(rootDir: projectRoot)
    try compositor.composeAll()
} catch {
    print("❌ 装裱失败: \(error)")
    exit(1)
}
