import AppKit

/// 过去 12 个月 token 柱状图。只消费 snapshot,不读取 ViewModel。
final class MonthlyTokenChartView: NSView {
    private let barsStack = NSStackView()
    private(set) var debugNormalizedHeights: [Double] = []
    private(set) var debugMonthLabels: [String] = []

    var debugBarCount: Int {
        barsStack.arrangedSubviews.count
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    /// 用新的 snapshot 替换图表内容。
    func configure(with snapshot: MonthlyTokenChartSnapshot) {
        clearBars()
        debugNormalizedHeights = snapshot.monthBuckets.map { clampNormalizedHeight($0.normalizedHeight) }
        debugMonthLabels = snapshot.monthBuckets.map(\.monthLabel)

        for bucket in snapshot.monthBuckets {
            let column = makeColumn(for: bucket)
            barsStack.addArrangedSubview(column)
        }
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        barsStack.translatesAutoresizingMaskIntoConstraints = false
        barsStack.orientation = .horizontal
        barsStack.alignment = .bottom
        barsStack.distribution = .fillEqually
        barsStack.spacing = 10

        addSubview(barsStack)
        NSLayoutConstraint.activate([
            barsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            barsStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            barsStack.topAnchor.constraint(equalTo: topAnchor),
            barsStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
    }

    private func clearBars() {
        for view in barsStack.arrangedSubviews {
            barsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func makeColumn(for bucket: MonthlyTokenBucket) -> NSView {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 8

        let barView = MonthlyTokenBarView()
        barView.translatesAutoresizingMaskIntoConstraints = false
        barView.normalizedHeight = bucket.normalizedHeight
        barView.fillColor = bucket.isCurrentMonth ? .controlAccentColor : .systemBlue
        barView.toolTip = "\(bucket.monthKey) · \(formatTokens(bucket.totalTokens)) tokens"

        let label = NSTextField(labelWithString: bucket.monthLabel)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .center

        column.addArrangedSubview(barView)
        column.addArrangedSubview(label)

        return column
    }

    private func formatTokens(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private func clampNormalizedHeight(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
}

/// 单根柱子的可测试绘制视图。完整高度由布局决定,柱子高度由 normalizedHeight 决定。
final class MonthlyTokenBarView: NSView {
    private var clampedNormalizedHeight: Double = 0

    var normalizedHeight: Double {
        get {
            clampedNormalizedHeight
        }
        set {
            clampedNormalizedHeight = clampNormalizedHeight(newValue)
            needsDisplay = true
        }
    }

    var fillColor: NSColor = .systemBlue {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        false
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 18, height: 160)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let barHeight = bounds.height * CGFloat(clampedNormalizedHeight)
        guard barHeight > 0 else { return }

        let rect = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: barHeight
        )
        fillColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
    }
}
