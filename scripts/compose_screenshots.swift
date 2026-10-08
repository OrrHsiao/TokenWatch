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

    private func renderPopoverContent(
        locale: String,
        in context: CGContext,
        canvasWidth: Int,
        canvasHeight: Int
    ) throws {
        let statusBarFile = rootDir.appendingPathComponent("snapshots/status_bar.png")
        if let sbData = try? Data(contentsOf: statusBarFile),
           let sbRep = NSBitmapImageRep(data: sbData),
           let sbCGImage = sbRep.cgImage {
            let sbHeight: CGFloat = 60
            let sbY = CGFloat(canvasHeight) - 450 - sbHeight
            let sbX = (CGFloat(canvasWidth) - CGFloat(sbRep.pixelsWide)) / 2
            let sbRect = CGRect(x: sbX, y: sbY, width: CGFloat(sbRep.pixelsWide), height: sbHeight)
            context.draw(sbCGImage, in: sbRect)
        }

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
