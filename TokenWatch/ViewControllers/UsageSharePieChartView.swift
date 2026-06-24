import AppKit

/// 展示 token 占比的饼图和图例。数据由外部 snapshot 注入,不读取 ViewModel。
final class UsageSharePieChartView: NSView {
    private static let maxLegendRowCount = 5

    private let titleLabel: NSTextField
    private let hoverLabel = NSTextField(labelWithString: "")
    private let titleContainer = NSView()
    private let drawingView = UsageSharePieDrawingView()
    private let legendStack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var slices: [UsageShareSlice] = []
    private var legendNameLabels: [NSTextField] = []
    private var legendValueLabels: [NSTextField] = []
    private var hoverLabelTrailingConstraint: NSLayoutConstraint?
    private var titleContainerTrailingConstraint: NSLayoutConstraint?
    private var bodyStackTrailingConstraint: NSLayoutConstraint?
    private var rootStackTrailingConstraint: NSLayoutConstraint?

    var debugTitle: String {
        titleLabel.stringValue
    }

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

    var debugHoverText: String {
        hoverLabel.stringValue
    }

    var debugHoverLabelTrailingAlignsWithChart: Bool {
        hoverLabelTrailingConstraint?.isActive == true
            && titleContainerTrailingConstraint?.isActive == true
            && bodyStackTrailingConstraint?.isActive == true
            && rootStackTrailingConstraint?.isActive == true
    }

    init(title: String) {
        self.titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        self.titleLabel = NSTextField(labelWithString: "占比")
        super.init(coder: coder)
        setupView()
    }

    func setTitle(_ title: String) {
        titleLabel.stringValue = title
    }

    /// 用新的 slices 替换饼图和图例。
    func configure(slices: [UsageShareSlice], language: AppLanguage = .zhHans) {
        let visibleSlices = slices.filter {
            $0.totalTokens > 0 && $0.percentage.isFinite && $0.percentage > 0
        }
        self.slices = Self.compactSlices(visibleSlices, language: language)
        emptyLabel.stringValue = AppStrings.text(.shareEmpty, language: language)
        drawingView.configure(slices: self.slices)
        rebuildLegend()
        updateHoverText(slice: nil)
        emptyLabel.isHidden = !self.slices.isEmpty
        legendStack.isHidden = self.slices.isEmpty
    }

    func debugSimulateHover(sliceID: String?) {
        guard let sliceID else {
            updateHoverText(slice: nil)
            return
        }
        updateHoverText(slice: slices.first { $0.id == sliceID })
    }

    private static func compactSlices(_ slices: [UsageShareSlice], language: AppLanguage) -> [UsageShareSlice] {
        guard slices.count > maxLegendRowCount else { return slices }

        let leadingCount = maxLegendRowCount - 1
        let leadingSlices = Array(slices.prefix(leadingCount))
        let overflowSlices = slices.dropFirst(leadingCount)
        let otherTokens = overflowSlices.reduce(0) { $0 + $1.totalTokens }
        let otherPercentage = overflowSlices.reduce(0) { $0 + $1.percentage }

        guard otherTokens > 0, otherPercentage > 0 else { return leadingSlices }
        return leadingSlices + [
            UsageShareSlice(
                id: "other",
                label: AppStrings.text(.shareOther, language: language),
                totalTokens: otherTokens,
                percentage: otherPercentage
            ),
        ]
    }

    private func setupView() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .left

        hoverLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        hoverLabel.textColor = .secondaryLabelColor
        hoverLabel.alignment = .right
        hoverLabel.lineBreakMode = .byTruncatingMiddle
        hoverLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        titleContainer.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        hoverLabel.translatesAutoresizingMaskIntoConstraints = false
        titleContainer.addSubview(titleLabel)
        titleContainer.addSubview(hoverLabel)

        drawingView.translatesAutoresizingMaskIntoConstraints = false
        drawingView.onHoverSliceChange = { [weak self] slice in
            self?.updateHoverText(slice: slice)
        }

        legendStack.orientation = .vertical
        legendStack.alignment = .width
        legendStack.spacing = 6
        legendStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        legendStack.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.isHidden = true

        let bodyStack = NSStackView(views: [drawingView, legendStack, emptyLabel])
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        bodyStack.orientation = .horizontal
        bodyStack.alignment = .top
        bodyStack.distribution = .fill
        bodyStack.spacing = 14
        bodyStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let rootStack = NSStackView(views: [titleContainer, bodyStack])
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.orientation = .vertical
        rootStack.alignment = .width
        rootStack.spacing = 10

        addSubview(rootStack)
        let hoverLabelTrailingConstraint = hoverLabel.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor)
        let titleContainerTrailingConstraint = titleContainer.trailingAnchor.constraint(equalTo: bodyStack.trailingAnchor)
        let bodyStackTrailingConstraint = bodyStack.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor)
        let rootStackTrailingConstraint = rootStack.trailingAnchor.constraint(equalTo: trailingAnchor)
        self.hoverLabelTrailingConstraint = hoverLabelTrailingConstraint
        self.titleContainerTrailingConstraint = titleContainerTrailingConstraint
        self.bodyStackTrailingConstraint = bodyStackTrailingConstraint
        self.rootStackTrailingConstraint = rootStackTrailingConstraint
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: hoverLabel.leadingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: titleContainer.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: titleContainer.bottomAnchor),
            hoverLabelTrailingConstraint,
            hoverLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStackTrailingConstraint,
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleContainer.leadingAnchor.constraint(equalTo: bodyStack.leadingAnchor),
            titleContainerTrailingConstraint,
            bodyStack.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            bodyStackTrailingConstraint,
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
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 1
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let valueLabel = NSTextField(labelWithString: formatPercentage(slice.percentage))
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UsageShareLegendRowView(views: [swatch, nameLabel, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 6
        row.toolTip = "\(slice.label) · \(CompactNumberFormatter.formatMillions(slice.totalTokens)) · \(formatPercentage(slice.percentage))"
        row.slice = slice
        row.onHoverSliceChange = { [weak self] slice in
            self?.updateHoverText(slice: slice)
        }
        legendNameLabels.append(nameLabel)
        legendValueLabels.append(valueLabel)

        NSLayoutConstraint.activate([
            swatch.widthAnchor.constraint(equalToConstant: 10),
            swatch.heightAnchor.constraint(equalToConstant: 10),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])
        return row
    }

    private func updateHoverText(slice: UsageShareSlice?) {
        guard let slice else {
            hoverLabel.stringValue = ""
            return
        }
        hoverLabel.stringValue = "\(slice.label) · \(CompactNumberFormatter.formatMillions(slice.totalTokens))"
    }

    private func formatPercentage(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

}

/// 饼图绘制视图。公开类型便于单元测试验证尺寸稳定。
final class UsageSharePieDrawingView: NSView {
    private var slices: [UsageShareSlice] = []
    private var hoverTrackingArea: NSTrackingArea?
    var onHoverSliceChange: ((UsageShareSlice?) -> Void)?

    override var intrinsicContentSize: NSSize {
        NSSize(width: 128, height: 128)
    }

    /// 用新的 slices 替换绘制内容。
    func configure(slices: [UsageShareSlice]) {
        self.slices = slices
        updateTrackingAreas()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
            self.hoverTrackingArea = nil
        }

        guard !slices.isEmpty else { return }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        updateHoverSlice(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoverSlice(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverSliceChange?(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 4, dy: 4)
        guard rect.width > 0, rect.height > 0 else { return }

        if slices.isEmpty {
            drawEmptyPie(in: rect)
            return
        }

        drawDonutSlices(in: rect)
    }

    private func drawDonutSlices(in rect: NSRect) {
        let totalTokens = slices.reduce(0) { $0 + $1.totalTokens }
        guard totalTokens > 0 else {
            drawEmptyPie(in: rect)
            return
        }

        let radius = min(rect.width, rect.height) / 2
        let innerRadius = radius * 0.58
        let center = NSPoint(x: rect.midX, y: rect.midY)
        var startAngle: CGFloat = 90

        for (index, slice) in slices.enumerated() {
            let sweep = CGFloat(slice.totalTokens) / CGFloat(totalTokens) * 360
            let endAngle = startAngle - sweep
            let path = donutSlicePath(
                center: center,
                outerRadius: radius,
                innerRadius: innerRadius,
                startAngle: startAngle,
                endAngle: endAngle
            )
            pieColor(at: index).setFill()
            path.fill()

            NSColor.windowBackgroundColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            startAngle = endAngle
        }
    }

    private func donutSlicePath(
        center: NSPoint,
        outerRadius: CGFloat,
        innerRadius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat
    ) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: point(center: center, radius: outerRadius, angle: startAngle))
        path.appendArc(
            withCenter: center,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )
        path.line(to: point(center: center, radius: innerRadius, angle: endAngle))
        path.appendArc(
            withCenter: center,
            radius: innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: false
        )
        path.close()
        return path
    }

    private func point(center: NSPoint, radius: CGFloat, angle: CGFloat) -> NSPoint {
        let radians = angle * .pi / 180
        return NSPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }

    private func drawEmptyPie(in rect: NSRect) {
        NSColor.separatorColor.setStroke()
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = 1
        path.stroke()
    }

    private func updateHoverSlice(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        onHoverSliceChange?(slice(at: location))
    }

    private func slice(at point: NSPoint) -> UsageShareSlice? {
        let rect = bounds.insetBy(dx: 4, dy: 4)
        guard rect.width > 0, rect.height > 0 else { return nil }

        let totalTokens = slices.reduce(0) { $0 + $1.totalTokens }
        guard totalTokens > 0 else { return nil }

        let radius = min(rect.width, rect.height) / 2
        let innerRadius = radius * 0.58
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance >= innerRadius, distance <= radius else { return nil }

        let angle = atan2(dy, dx) * 180 / .pi
        var clockwiseDegreesFromTop = 90 - angle
        while clockwiseDegreesFromTop < 0 {
            clockwiseDegreesFromTop += 360
        }
        while clockwiseDegreesFromTop >= 360 {
            clockwiseDegreesFromTop -= 360
        }

        var accumulated: CGFloat = 0
        for slice in slices {
            let sweep = CGFloat(slice.totalTokens) / CGFloat(totalTokens) * 360
            if clockwiseDegreesFromTop <= accumulated + sweep {
                return slice
            }
            accumulated += sweep
        }
        return slices.last
    }
}

private final class UsageShareLegendRowView: NSStackView {
    var slice: UsageShareSlice? {
        didSet {
            updateTrackingAreas()
        }
    }
    var onHoverSliceChange: ((UsageShareSlice?) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
            self.hoverTrackingArea = nil
        }

        guard slice != nil, !isHidden else { return }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverSliceChange?(slice)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverSliceChange?(nil)
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
