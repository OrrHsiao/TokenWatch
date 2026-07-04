import Foundation

enum RecentSessionPaginationItem: Equatable {
    case page(Int)
    case ellipsis
}

/// 会话列表分页快照,把当前页、展示范围和折叠页码集中在一个可测试的纯模型里。
struct RecentSessionPagination: Equatable {
    let totalCount: Int
    let pageSize: Int
    let currentPage: Int
    let totalPages: Int
    let rowRange: Range<Int>
    let items: [RecentSessionPaginationItem]

    var canGoPrevious: Bool {
        currentPage > 1
    }

    var canGoNext: Bool {
        currentPage < totalPages
    }

    var displayRangeText: String {
        guard totalCount > 0 else {
            return "显示 0-0 / 共 0 个会话"
        }
        let start = Self.formatInt(rowRange.lowerBound + 1)
        let end = Self.formatInt(rowRange.upperBound)
        let total = Self.formatInt(totalCount)
        return "显示 \(start)-\(end) / 共 \(total) 个会话"
    }

    init(totalCount: Int, pageSize: Int, currentPage: Int) {
        let safeTotalCount = max(0, totalCount)
        let safePageSize = max(1, pageSize)
        let calculatedTotalPages = max(1, Int(ceil(Double(safeTotalCount) / Double(safePageSize))))
        let clampedCurrentPage = min(max(1, currentPage), calculatedTotalPages)
        let lowerBound = min((clampedCurrentPage - 1) * safePageSize, safeTotalCount)
        let upperBound = min(lowerBound + safePageSize, safeTotalCount)

        self.totalCount = safeTotalCount
        self.pageSize = safePageSize
        self.currentPage = clampedCurrentPage
        self.totalPages = calculatedTotalPages
        rowRange = lowerBound..<upperBound
        items = Self.makeItems(currentPage: clampedCurrentPage, totalPages: calculatedTotalPages)
    }

    private static func makeItems(currentPage: Int, totalPages: Int) -> [RecentSessionPaginationItem] {
        guard totalPages > 5 else {
            return (1...totalPages).map(RecentSessionPaginationItem.page)
        }
        if currentPage <= 3 {
            return [.page(1), .page(2), .page(3), .ellipsis, .page(totalPages)]
        }
        if currentPage >= totalPages - 2 {
            return [.page(1), .ellipsis, .page(totalPages - 2), .page(totalPages - 1), .page(totalPages)]
        }
        return [
            .page(1),
            .ellipsis,
            .page(currentPage - 1),
            .page(currentPage),
            .page(currentPage + 1),
            .ellipsis,
            .page(totalPages),
        ]
    }

    private static func formatInt(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
