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

            // 3. 右侧：日期时间按截图语言绘制并右对齐，避免英文截图出现中文日期；
            //    其左为系统常驻图标 (Wi-Fi、聚焦、控制中心、Siri，从 status_bar.png 提取 x: 3290..3550)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let clockAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 26),
                .foregroundColor: NSColor(white: 0.93, alpha: 1.0)
            ]
            let clockText = Self.menuBarClockText(locale: locale) as NSString
            let clockSize = clockText.size(withAttributes: clockAttrs)
            let clockX = CGFloat(canvasWidth) - 48 - clockSize.width
            clockText.draw(at: NSPoint(x: clockX, y: sbY + (sbHeight - clockSize.height) / 2), withAttributes: clockAttrs)
            NSGraphicsContext.restoreGraphicsState()

            let sysWidth: CGFloat = 260
            if let sysCrop = sbCGImage.cropping(to: CGRect(x: 3290, y: 0, width: Int(sysWidth), height: 60)) {
                let sysRect = CGRect(x: clockX - 32 - sysWidth, y: sbY, width: sysWidth, height: sbHeight)
                context.draw(sysCrop, in: sysRect)
            }
        }

        // 4. 正对 Popover 视图上方：TokenWatch 状态栏项目，使用 App 以真实状态栏绘制逻辑导出的 2x 图像
        if let statusItemRep = findStatusBarItemImage(locale: locale),
           let statusItemCGImage = statusItemRep.cgImage {
            let itemWidth = CGFloat(statusItemRep.pixelsWide)
            let itemHeight = CGFloat(statusItemRep.pixelsHigh)
            let itemRect = CGRect(
                x: (popRect.midX - itemWidth / 2).rounded(),
                y: (sbY + (sbHeight - itemHeight) / 2).rounded(),
                width: itemWidth,
                height: itemHeight
            )
            context.draw(statusItemCGImage, in: itemRect)
        } else {
            print("⚠️ 未找到 \(locale) 的状态栏项目原图")
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

        // UI 测试 Runner 容器内的原图比 raw 目录新时先同步，否则 run_ui_tests 抓到的新界面会被已提交的旧原图挡住
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let runnerTmpURL = homeDir
            .appendingPathComponent("Library/Containers/com.xiaoao.TokenWatchUITests.xctrunner/Data/tmp/tokenwatch_screenshots/raw/\(locale)/\(screenID).png")
        if isFile(runnerTmpURL, newerThan: rawURL),
           let data = try? Data(contentsOf: runnerTmpURL),
           let rep = NSBitmapImageRep(data: data) {
            try? FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true)
            try? data.write(to: rawURL)
            print("  ✓ 已从 UI 测试 Runner 同步 \(locale) 的 \(screenID).png")
            return rep
        }

        guard let data = try? Data(contentsOf: rawURL) else { return nil }
        return NSBitmapImageRep(data: data)
    }

    /// 菜单栏右侧的日期时间，按截图语言格式化。
    /// 日期取生成当天，与 demo 数据的“今日”一致；时间固定，保证同一天重复生成结果不变。
    private static func menuBarClockText(locale: String, now: Date = Date()) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(bySettingHour: 11, minute: 45, second: 0, of: now) ?? now
        let formatter = DateFormatter()
        formatter.calendar = calendar
        if locale == "zh-Hans" {
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M月d日 EEE HH:mm"
        } else {
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "EEE MMM d  h:mm a"
        }
        return formatter.string(from: date)
    }

    private func findPopoverImage(locale: String) -> NSBitmapImageRep? {
        if !didExportPopoverSnapshots {
            _ = exportPopoverSnapshotsFromBinary()
            didExportPopoverSnapshots = true
        }

        let rawURL = rootDir.appendingPathComponent("snapshots/raw/\(locale)/01-menu-bar-popover.png")
        guard let data = try? Data(contentsOf: rawURL) else { return nil }
        return NSBitmapImageRep(data: data)
    }

    /// `candidate` 存在且修改时间晚于 `reference`（或 `reference` 不存在）时返回 true。
    private func isFile(_ candidate: URL, newerThan reference: URL) -> Bool {
        let fileManager = FileManager.default
        guard let candidateDate = (try? fileManager.attributesOfItem(atPath: candidate.path))?[.modificationDate] as? Date else {
            return false
        }
        guard let referenceDate = (try? fileManager.attributesOfItem(atPath: reference.path))?[.modificationDate] as? Date else {
            return true
        }
        return candidateDate > referenceDate
    }

    /// 状态栏项目原图与弹窗原图由同一次 App 导出生成，读取前先确保已尝试导出。
    private func findStatusBarItemImage(locale: String) -> NSBitmapImageRep? {
        if !didExportPopoverSnapshots {
            _ = exportPopoverSnapshotsFromBinary()
            didExportPopoverSnapshots = true
        }

        let rawURL = rootDir.appendingPathComponent("snapshots/raw/\(locale)/\(Self.statusBarItemFileName)")
        guard let data = try? Data(contentsOf: rawURL) else { return nil }
        return NSBitmapImageRep(data: data)
    }

    private static let statusBarItemFileName = "01-menu-bar-status-item.png"

    /// App 导出时各类原图的标记前缀与写入 raw 目录的文件名。
    private static let exportedSnapshotKinds: [(prefix: String, fileName: String)] = [
        ("TOKENWATCH_SNAPSHOT", "01-menu-bar-popover.png"),
        ("TOKENWATCH_STATUSBAR", statusBarItemFileName)
    ]

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
            var current: (locale: String, fileName: String)?
            var base64Lines: [String] = []

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let kind = Self.exportedSnapshotKinds.first(where: { trimmed.hasPrefix("\($0.prefix)_START:") }) {
                    current = (String(trimmed.dropFirst("\(kind.prefix)_START:".count)), kind.fileName)
                    base64Lines.removeAll()
                } else if Self.exportedSnapshotKinds.contains(where: { trimmed.hasPrefix("\($0.prefix)_END:") }) {
                    if let current,
                       let pngData = Data(base64Encoded: base64Lines.joined()) {
                        let targetDir = rootDir.appendingPathComponent("snapshots/raw/\(current.locale)")
                        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
                        let fileURL = targetDir.appendingPathComponent(current.fileName)
                        try? pngData.write(to: fileURL)
                        print("  ✓ 自动从 App 二进制生成了 \(current.locale) 的 \(current.fileName)")
                    }
                    current = nil
                } else if current != nil {
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
