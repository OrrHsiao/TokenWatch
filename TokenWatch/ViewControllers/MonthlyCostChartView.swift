import AppKit

/// 过去 12 个月费用柱状图。只消费 snapshot,不读取 ViewModel。
final class MonthlyCostChartView: NSView {
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

    /// 用新的 snapshot 替换费用图表内容。
    func configure(with snapshot: MonthlyTokenChartSnapshot) {
        clearBars()
        debugNormalizedHeights = snapshot.monthBuckets.map { clampNormalizedCostHeight($0.normalizedCostHeight) }
        debugMonthLabels = snapshot.monthBuckets.map(\.monthLabel)

        for bucket in snapshot.monthBuckets {
            barsStack.addArrangedSubview(makeColumn(for: bucket))
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

        let barView = MonthlyCostBarView()
        barView.translatesAutoresizingMaskIntoConstraints = false
        barView.normalizedHeight = bucket.normalizedCostHeight
        barView.fillColor = bucket.isCurrentMonth ? .controlAccentColor : .systemGreen
        barView.toolTip = "\(bucket.monthKey) · \(formatCurrency(bucket.totalCost))"

        let label = NSTextField(labelWithString: bucket.monthLabel)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .center

        column.addArrangedSubview(barView)
        column.addArrangedSubview(label)

        return column
    }

    private func formatCurrency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}

private func clampNormalizedCostHeight(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
}

/// 单根费用柱子的可测试绘制视图。完整高度由布局决定,柱子高度由 normalizedHeight 决定。
final class MonthlyCostBarView: NSView {
    private var clampedNormalizedHeight: Double = 0

    var normalizedHeight: Double {
        get {
            clampedNormalizedHeight
        }
        set {
            clampedNormalizedHeight = clampNormalizedCostHeight(newValue)
            needsDisplay = true
        }
    }

    var fillColor: NSColor = .systemGreen {
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

        let rect = NSRect(x: 0, y: 0, width: bounds.width, height: barHeight)
        fillColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
    }
}
