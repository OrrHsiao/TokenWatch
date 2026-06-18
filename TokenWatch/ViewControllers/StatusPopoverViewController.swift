import AppKit

/// 状态栏 popover 内容控制器,展示近 22 周跨 provider token 日历热力图。
@MainActor
final class StatusPopoverViewController: NSViewController {

    nonisolated static let contentSize = NSSize(width: 370, height: 180)
    private static let outerMargin: CGFloat = 14
    private static let tileSpacing: CGFloat = 3
    private static let gridColumnCount = 22
    private static let gridRowCount = 7
    private static let collectionHeight =
        CalendarHeatmapCollectionViewItem.tileSize.height * CGFloat(gridRowCount)
        + tileSpacing * CGFloat(gridRowCount - 1)
    private static let collectionWidth =
        CalendarHeatmapCollectionViewItem.tileSize.width * CGFloat(gridColumnCount)
        + tileSpacing * CGFloat(gridColumnCount - 1)

    private let viewModel: TokenStatsViewModel
    private let nowProvider: () -> Date
    private let calendar: Calendar
    private var observerToken: TokenStatsViewModel.ObservationToken?
    private var snapshot: CalendarHeatmapSnapshot?
    private var rangeTotalText = ""
    private var hoverText: String?

    private let titleLabel = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "")
    private let hoverLabel = NSTextField(labelWithString: "")
    private let collectionView = NSCollectionView()

    var debugMonthTitle: String { titleLabel.stringValue }
    var debugTotalText: String { totalLabel.stringValue }
    var debugHoverText: String { hoverLabel.stringValue }
    var debugCollectionView: NSCollectionView? { collectionView }
    var debugWeekdayLabelCount: Int { 0 }
    var debugCollectionItemCount: Int { snapshot?.cells.count ?? 0 }
    var debugCollectionHeight: CGFloat { Self.collectionHeight }
    static var debugExpectedCollectionHeight: CGFloat { collectionHeight }
    var debugHoverLabelTrailingAlignsWithCollectionView: Bool {
        hasConstraint(
            firstItem: hoverLabel,
            firstAttribute: .trailing,
            secondItem: collectionView,
            secondAttribute: .trailing,
            constant: 0
        )
    }
    var debugHoverLabelLeadingAlignsWithCollectionView: Bool {
        hasConstraint(
            firstItem: hoverLabel,
            firstAttribute: .leading,
            secondItem: collectionView,
            secondAttribute: .leading,
            constant: 0
        )
    }
    var debugHoverLabelSitsJustAboveCollectionView: Bool {
        hasConstraint(
            firstItem: hoverLabel,
            firstAttribute: .bottom,
            secondItem: collectionView,
            secondAttribute: .top,
            constant: -1
        )
    }
    var debugCollectionViewBottomFitsInRootBounds: Bool {
        let frameInRoot = collectionView.convert(collectionView.bounds, to: view)
        return frameInRoot.minY >= Self.outerMargin
            && frameInRoot.maxY <= view.bounds.maxY - Self.outerMargin
    }
    func debugHasCell(at item: Int) -> Bool { cell(at: item) != nil }
    func debugUpdateHoverText(_ text: String?) { updateHoverText(text) }

    private func isConstraintItem(_ item: Any?, identicalTo target: NSView) -> Bool {
        guard let item = item as AnyObject? else { return false }
        return item === target
    }

    private func hasConstraint(
        firstItem: NSView,
        firstAttribute: NSLayoutConstraint.Attribute,
        secondItem: NSView,
        secondAttribute: NSLayoutConstraint.Attribute,
        constant: CGFloat
    ) -> Bool {
        view.constraints.contains { constraint in
            guard constraint.isActive,
                  constraint.firstAttribute == firstAttribute,
                  constraint.secondAttribute == secondAttribute,
                  constraint.multiplier == 1,
                  constraint.constant == constant else {
                return false
            }

            return isConstraintItem(constraint.firstItem, identicalTo: firstItem)
                && isConstraintItem(constraint.secondItem, identicalTo: secondItem)
        }
    }

    init(
        viewModel: TokenStatsViewModel,
        nowProvider: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.viewModel = viewModel
        self.nowProvider = nowProvider
        self.calendar = calendar
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.contentSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("StatusPopoverViewController 必须用 init(viewModel:) 构造")
    }

    override func loadView() {
        view = StatusPopoverRootView(frame: NSRect(origin: .zero, size: Self.contentSize))
        setupSubviews()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        render()
        observerToken = viewModel.observe { [weak self] _ in
            self?.render()
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let observerToken {
                viewModel.removeObserver(observerToken)
            }
        }
    }

    private func setupSubviews() {
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor

        totalLabel.font = .systemFont(ofSize: 12)
        totalLabel.textColor = .secondaryLabelColor

        hoverLabel.font = .systemFont(ofSize: 12, weight: .medium)
        hoverLabel.textColor = .secondaryLabelColor
        hoverLabel.alignment = .right
        hoverLabel.lineBreakMode = .byTruncatingMiddle
        hoverLabel.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = NSStackView(views: [titleLabel, totalLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 2
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = Self.tileSpacing
        layout.minimumLineSpacing = Self.tileSpacing
        layout.itemSize = CalendarHeatmapCollectionViewItem.tileSize
        layout.sectionInset = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false
        collectionView.dataSource = self
        collectionView.register(
            CalendarHeatmapCollectionViewItem.self,
            forItemWithIdentifier: CalendarHeatmapCollectionViewItem.reuseIdentifier
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerStack)
        view.addSubview(hoverLabel)
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -14),

            hoverLabel.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor),
            hoverLabel.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor),
            hoverLabel.bottomAnchor.constraint(equalTo: collectionView.topAnchor, constant: -1),

            collectionView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 14),
            collectionView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            collectionView.widthAnchor.constraint(equalToConstant: Self.collectionWidth),
            collectionView.heightAnchor.constraint(equalToConstant: Self.collectionHeight),
            collectionView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -14),
        ])
    }

    private func render() {
        let now = nowProvider()
        let snapshot = CalendarHeatmapBuilder.build(
            states: viewModel.states,
            month: now,
            now: now,
            calendar: calendar
        )
        self.snapshot = snapshot

        titleLabel.stringValue = snapshot.monthTitle
        rangeTotalText = "近22周 \(CompactNumberFormatter.format(snapshot.monthTotalTokens)) tokens"
        applyTotalText()
        applyHoverText()
        collectionView.reloadData()
    }

    private func updateHoverText(_ text: String?) {
        hoverText = text
        applyHoverText()
    }

    private func applyTotalText() {
        totalLabel.stringValue = rangeTotalText
    }

    private func applyHoverText() {
        hoverLabel.stringValue = hoverText ?? ""
    }

    private func cell(at item: Int) -> CalendarHeatmapCell? {
        guard let cells = snapshot?.cells,
              cells.indices.contains(item) else {
            return nil
        }

        return cells[item]
    }
}

/// 跟随系统外观刷新 popover 背景色。
final class StatusPopoverRootView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateBackgroundColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("StatusPopoverRootView 不支持 storyboard 初始化")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackgroundColor()
    }

    private func updateBackgroundColor() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
}

extension StatusPopoverViewController: NSCollectionViewDataSource {
    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        snapshot?.cells.count ?? 0
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: CalendarHeatmapCollectionViewItem.reuseIdentifier,
            for: indexPath
        )
        guard let heatmapItem = item as? CalendarHeatmapCollectionViewItem,
              let cell = cell(at: indexPath.item) else {
            return item
        }

        heatmapItem.onHoverTextChange = { [weak self] text in
            self?.updateHoverText(text)
        }
        heatmapItem.configure(with: cell)
        return heatmapItem
    }
}
