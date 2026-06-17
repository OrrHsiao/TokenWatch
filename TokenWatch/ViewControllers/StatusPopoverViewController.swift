import AppKit

/// 状态栏 popover 内容控制器,展示本月跨 provider token 日历热力图。
@MainActor
final class StatusPopoverViewController: NSViewController {

    private static let contentSize = NSSize(width: 300, height: 300)
    private static let outerMargin: CGFloat = 14
    private static let collectionHeight: CGFloat = 188

    private let viewModel: TokenStatsViewModel
    private let nowProvider: () -> Date
    private let calendar: Calendar
    private var observerToken: TokenStatsViewModel.ObservationToken?
    private var snapshot: CalendarHeatmapSnapshot?

    private let titleLabel = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "")
    private let weekdayStack = NSStackView()
    private let collectionView = NSCollectionView()

    var debugMonthTitle: String { titleLabel.stringValue }
    var debugCollectionView: NSCollectionView? { collectionView }
    var debugWeekdayLabelCount: Int { weekdayStack.arrangedSubviews.count }
    var debugCollectionItemCount: Int { snapshot?.cells.count ?? 0 }
    var debugCollectionHeight: CGFloat { Self.collectionHeight }
    static var debugExpectedCollectionHeight: CGFloat { collectionHeight }
    var debugCollectionViewBottomFitsInRootBounds: Bool {
        collectionView.frame.minY >= Self.outerMargin
            && collectionView.frame.maxY <= view.bounds.maxY - Self.outerMargin
    }
    func debugHasCell(at item: Int) -> Bool { cell(at: item) != nil }

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
        view = NSView(frame: NSRect(origin: .zero, size: Self.contentSize))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
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

        let headerStack = NSStackView(views: [titleLabel, totalLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 2
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        weekdayStack.orientation = .horizontal
        weekdayStack.distribution = .fillEqually
        weekdayStack.spacing = 4
        weekdayStack.translatesAutoresizingMaskIntoConstraints = false

        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        layout.itemSize = NSSize(width: 34, height: 28)
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
        view.addSubview(weekdayStack)
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -14),

            weekdayStack.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 14),
            weekdayStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            weekdayStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            weekdayStack.heightAnchor.constraint(equalToConstant: 18),

            collectionView.topAnchor.constraint(equalTo: weekdayStack.bottomAnchor, constant: 6),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
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
        totalLabel.stringValue = "本月 \(CompactNumberFormatter.format(snapshot.monthTotalTokens)) tokens"
        renderWeekdayLabels(snapshot.weekdaySymbols)
        collectionView.reloadData()
    }

    private func renderWeekdayLabels(_ symbols: [String]) {
        if weekdayStack.arrangedSubviews.count == symbols.count {
            for (view, symbol) in zip(weekdayStack.arrangedSubviews, symbols) {
                (view as? NSTextField)?.stringValue = symbol
            }
            return
        }

        weekdayStack.arrangedSubviews.forEach { view in
            weekdayStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for symbol in symbols {
            let label = NSTextField(labelWithString: symbol)
            label.alignment = .center
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.textColor = .secondaryLabelColor
            weekdayStack.addArrangedSubview(label)
        }
    }

    private func cell(at item: Int) -> CalendarHeatmapCell? {
        guard let cells = snapshot?.cells,
              cells.indices.contains(item) else {
            return nil
        }

        return cells[item]
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

        heatmapItem.configure(with: cell)
        return heatmapItem
    }
}
