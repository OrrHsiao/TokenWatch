import AppKit

/// 展示 token 占比的饼图和图例。数据由外部 snapshot 注入,不读取 ViewModel。
final class UsageSharePieChartView: NSView {
    private let titleLabel: NSTextField
    private let drawingView = UsageSharePieDrawingView()
    private let legendStack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "暂无数据")
    private var slices: [UsageShareSlice] = []
    private var legendNameLabels: [NSTextField] = []
    private var legendValueLabels: [NSTextField] = []

    let debugTitle: String

    var debugLegendRowCount: Int {
        legendStack.arrangedSubviews.count
    }

    var debugSliceLabels: [String] {
        slices.map(\.label)
    }

    var debugPercentages: [Double] {
        slices.map(\.percentage)
    }

    var debugLegendNameLabels: [String] {
        legendNameLabels.map(\.stringValue)
    }

    var debugLegendValueLabels: [String] {
        legendValueLabels.map(\.stringValue)
    }

    var debugLegendNameLineBreakModes: [NSLineBreakMode] {
        legendNameLabels.map(\.lineBreakMode)
    }

    init(title: String) {
        self.debugTitle = title
        self.titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        self.debugTitle = "占比"
        self.titleLabel = NSTextField(labelWithString: "占比")
        super.init(coder: coder)
        setupView()
    }

    /// 用新的 slices 替换饼图和图例。
    func configure(slices: [UsageShareSlice]) {
        self.slices = slices.filter {
            $0.totalTokens > 0 && $0.percentage.isFinite && $0.percentage > 0
        }
        drawingView.configure(slices: self.slices)
        rebuildLegend()
        emptyLabel.isHidden = !self.slices.isEmpty
        legendStack.isHidden = self.slices.isEmpty
    }

    private func setupView() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor

        drawingView.translatesAutoresizingMaskIntoConstraints = false

        legendStack.orientation = .vertical
        legendStack.alignment = .width
        legendStack.spacing = 6
        legendStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        legendStack.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.isHidden = true

        let bodyStack = NSStackView(views: [drawingView, legendStack, emptyLabel])
        bodyStack.orientation = .horizontal
        bodyStack.alignment = .centerY
        bodyStack.distribution = .fill
        bodyStack.spacing = 14
        bodyStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let rootStack = NSStackView(views: [titleLabel, bodyStack])
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.orientation = .vertical
        rootStack.alignment = .width
        rootStack.spacing = 10

        addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            drawingView.widthAnchor.constraint(equalToConstant: 128),
            drawingView.heightAnchor.constraint(equalToConstant: 128),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 170),
        ])
    }

    private func rebuildLegend() {
        for view in legendStack.arrangedSubviews {
            legendStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        legendNameLabels.removeAll()
        legendValueLabels.removeAll()

        for (index, slice) in slices.enumerated() {
            legendStack.addArrangedSubview(makeLegendRow(for: slice, color: pieColor(at: index)))
        }
    }

    private func makeLegendRow(for slice: UsageShareSlice, color: NSColor) -> NSView {
        let swatch = UsageShareLegendSwatchView(color: color)
        swatch.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: slice.label)
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.lineBreakMode = .byClipping
        nameLabel.maximumNumberOfLines = 1
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let valueLabel = NSTextField(labelWithString: "\(formatPercentage(slice.percentage)) · \(CompactNumberFormatter.format(slice.totalTokens))")
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [swatch, nameLabel, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 6
        row.toolTip = "\(slice.label) · \(formatTokens(slice.totalTokens)) tokens · \(formatPercentage(slice.percentage))"
        legendNameLabels.append(nameLabel)
        legendValueLabels.append(valueLabel)

        NSLayoutConstraint.activate([
            swatch.widthAnchor.constraint(equalToConstant: 10),
            swatch.heightAnchor.constraint(equalToConstant: 10),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 104),
        ])
        return row
    }

    private func formatPercentage(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private func formatTokens(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

/// 饼图绘制视图。公开类型便于单元测试验证尺寸稳定。
final class UsageSharePieDrawingView: NSView {
    private var slices: [UsageShareSlice] = []

    override var intrinsicContentSize: NSSize {
        NSSize(width: 128, height: 128)
    }

    /// 用新的 slices 替换绘制内容。
    func configure(slices: [UsageShareSlice]) {
        self.slices = slices
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 4, dy: 4)
        guard rect.width > 0 && rect.height > 0 else { return }

        if slices.isEmpty {
            drawEmptyPie(in: rect)
            return
        }

        if slices.count == 1 {
            pieColor(at: 0).setFill()
            NSBezierPath(ovalIn: rect).fill()
            return
        }

        let radius = min(rect.width, rect.height) / 2
        let center = NSPoint(x: rect.midX, y: rect.midY)
        var startAngle: CGFloat = 90

        for (index, slice) in slices.enumerated() {
            let sweep = CGFloat(slice.percentage * 360)
            let endAngle = startAngle - sweep
            let path = NSBezierPath()
            path.move(to: center)
            path.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: true
            )
            path.close()
            pieColor(at: index).setFill()
            path.fill()

            NSColor.windowBackgroundColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            startAngle = endAngle
        }
    }

    private func drawEmptyPie(in rect: NSRect) {
        NSColor.separatorColor.setStroke()
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = 1
        path.stroke()
    }
}

private final class UsageShareLegendSwatchView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = 5
    }

    required init?(coder: NSCoder) {
        self.color = .systemBlue
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = 5
    }
}

private let pieColors: [NSColor] = [
    .systemBlue,
    .systemGreen,
    .systemOrange,
    .systemPurple,
    .systemRed,
    .systemTeal,
    .systemPink,
    .systemBrown,
]

private func pieColor(at index: Int) -> NSColor {
    pieColors[index % pieColors.count]
}
