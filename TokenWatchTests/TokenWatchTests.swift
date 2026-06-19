//
//  TokenWatchTests.swift
//  TokenWatchTests
//
//  Created by OrrHsiao on 2026/6/13.
//

import Testing
import AppKit
@testable import TokenWatch

struct TokenWatchTests {

    @MainActor
    @Test func mainWindowUsesNativeSidebarSplitLayout() throws {
        let viewController = ViewController()
        viewController.loadViewIfNeeded()

        let splitView = try #require(viewController.view.firstDescendant(ofType: NSSplitView.self))
        #expect(splitView.isVertical)
        #expect(splitView.arrangedSubviews.count == 2)
    }

    @MainActor
    @Test func sidebarListsProvidersInRegistryOrder() throws {
        let viewController = ViewController()
        viewController.loadViewIfNeeded()

        let sidebar = try #require(viewController.view.firstDescendant(ofType: NSTableView.self))
        #expect(sidebar.style == .sourceList)
        #expect(sidebar.numberOfRows == ProviderRegistry.allProviders.count)

        let displayedTitles = (0..<sidebar.numberOfRows).compactMap { row in
            (sidebar.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)?
                .textField?
                .stringValue
        }
        #expect(displayedTitles == ProviderRegistry.allProviders.map(\.displayName))
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }
        for subview in subviews {
            if let match = subview.firstDescendant(ofType: type) {
                return match
            }
        }
        return nil
    }
}
