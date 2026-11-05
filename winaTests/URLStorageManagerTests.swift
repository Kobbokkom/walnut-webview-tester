//
//  URLStorageManagerTests.swift
//  winaTests
//
//  Tests for URLStorageManager bookmark and history functionality.
//

import XCTest
@testable import wina

final class URLStorageManagerTests: XCTestCase {

    var manager: URLStorageManager!

    // Store original state to restore after tests
    private var originalBookmarksData: Data?
    private var originalHistoryData: Data?

    private let bookmarksKey = "bookmarkedURLs"
    private let historyKey = "recentURLs"

    override func setUp() {
        super.setUp()

        // Save original UserDefaults state
        originalBookmarksData = UserDefaults.standard.data(forKey: bookmarksKey)
        originalHistoryData = UserDefaults.standard.data(forKey: historyKey)

        // Clear state for fresh tests
        UserDefaults.standard.removeObject(forKey: bookmarksKey)
        UserDefaults.standard.removeObject(forKey: historyKey)

        manager = URLStorageManager.shared

        // Force reload with empty state
        // Since we can't access private methods, we clear by removing all items
        clearAllBookmarks()
        clearHistory()
    }

    override func tearDown() {
        // Clean up
        clearAllBookmarks()
        clearHistory()

        // Restore original UserDefaults state
        if let data = originalBookmarksData {
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        }
        if let data = originalHistoryData {
            UserDefaults.standard.set(data, forKey: historyKey)
        }

        manager = nil
        super.tearDown()
    }

    private func clearAllBookmarks() {
        let urls = manager.bookmarks
        for url in urls {
            manager.removeBookmark(url)
        }
    }

    private func clearHistory() {
        manager.clearHistory()
    }

    // MARK: - Bookmark Tests

    func testEveryBookmarkMutationPersistsTheCurrentSnapshot() throws {
        for index in 0..<20 {
            let url = "https://persist\(index).example"
            manager.addBookmark(url)
            var data = try XCTUnwrap(UserDefaults.standard.data(forKey: bookmarksKey))
            XCTAssertEqual(try JSONDecoder().decode([String].self, from: data), manager.bookmarks)
            manager.removeBookmark(url)
            data = try XCTUnwrap(UserDefaults.standard.data(forKey: bookmarksKey))
            XCTAssertEqual(try JSONDecoder().decode([String].self, from: data), manager.bookmarks)
        }
    }

    func testEveryHistoryMutationPersistsTheCurrentSnapshot() throws {
        for index in 0..<20 {
            manager.addToHistory("https://persist\(index).example")
            let data = try XCTUnwrap(UserDefaults.standard.data(forKey: historyKey))
            XCTAssertEqual(try JSONDecoder().decode([String].self, from: data), manager.history)
        }
        manager.removeFromHistory("https://persist19.example")
        var data = try XCTUnwrap(UserDefaults.standard.data(forKey: historyKey))
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: data), manager.history)
        manager.clearHistory()
        data = try XCTUnwrap(UserDefaults.standard.data(forKey: historyKey))
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: data), [])
    }

    func testAddBookmark() {
        let url = "https://example.com"

        manager.addBookmark(url)

        XCTAssertTrue(manager.bookmarks.contains(url))
        XCTAssertTrue(manager.isBookmarked(url))
    }

    func testAddBookmarkInsertsAtFront() {
        manager.addBookmark("https://first.com")
        manager.addBookmark("https://second.com")

        XCTAssertEqual(manager.bookmarks.first, "https://second.com")
        XCTAssertEqual(manager.bookmarks.last, "https://first.com")
    }

    func testAddBookmarkPreventsDuplicates() {
        let url = "https://example.com"

        manager.addBookmark(url)
        manager.addBookmark(url)

        let count = manager.bookmarks.filter { $0 == url }.count
        XCTAssertEqual(count, 1)
    }

    func testAddEmptyBookmarkIsIgnored() {
        let initialCount = manager.bookmarks.count

        manager.addBookmark("")

        XCTAssertEqual(manager.bookmarks.count, initialCount)
    }

    func testRemoveBookmark() {
        let url = "https://example.com"
        manager.addBookmark(url)

        manager.removeBookmark(url)

        XCTAssertFalse(manager.bookmarks.contains(url))
        XCTAssertFalse(manager.isBookmarked(url))
    }

    func testRemoveNonexistentBookmarkDoesNotCrash() {
        manager.removeBookmark("https://nonexistent.com")

        // Should complete without error
        XCTAssertTrue(true)
    }

    func testIsBookmarkedReturnsTrueForBookmarkedURL() {
        let url = "https://example.com"
        manager.addBookmark(url)

        XCTAssertTrue(manager.isBookmarked(url))
    }

    func testIsBookmarkedReturnsFalseForNonBookmarkedURL() {
        XCTAssertFalse(manager.isBookmarked("https://notbookmarked.com"))
    }

    func testToggleBookmarkAddsWhenNotBookmarked() {
        let url = "https://example.com"
        XCTAssertFalse(manager.isBookmarked(url))

        manager.toggleBookmark(url)

        XCTAssertTrue(manager.isBookmarked(url))
    }

    func testToggleBookmarkRemovesWhenBookmarked() {
        let url = "https://example.com"
        manager.addBookmark(url)

        manager.toggleBookmark(url)

        XCTAssertFalse(manager.isBookmarked(url))
    }

    // MARK: - History Tests

    func testAddToHistory() {
        let url = "https://example.com"

        manager.addToHistory(url)

        XCTAssertTrue(manager.history.contains(url))
    }

    func testAddToHistoryInsertsAtFront() {
        manager.addToHistory("https://first.com")
        manager.addToHistory("https://second.com")

        XCTAssertEqual(manager.history.first, "https://second.com")
    }

    func testAddToHistoryMovesExistingToTop() {
        manager.addToHistory("https://first.com")
        manager.addToHistory("https://second.com")
        manager.addToHistory("https://first.com")  // Re-add first

        XCTAssertEqual(manager.history.first, "https://first.com")

        // Should only appear once
        let count = manager.history.filter { $0 == "https://first.com" }.count
        XCTAssertEqual(count, 1)
    }

    func testAddEmptyHistoryIsIgnored() {
        let initialCount = manager.history.count

        manager.addToHistory("")

        XCTAssertEqual(manager.history.count, initialCount)
    }

    func testHistoryLimitedToMaxCount() {
        // Add more than max (50) items
        for idx in 0..<60 {
            manager.addToHistory("https://example\(idx).com")
        }

        XCTAssertLessThanOrEqual(manager.history.count, 50)
    }

    func testHistoryPreservesNewestItems() {
        // Add 60 items
        for idx in 0..<60 {
            manager.addToHistory("https://example\(idx).com")
        }

        // The newest item (59) should be at the top
        XCTAssertEqual(manager.history.first, "https://example59.com")

        // Old items (0-9) should be removed
        XCTAssertFalse(manager.history.contains("https://example0.com"))
    }

    func testRemoveFromHistory() {
        let url = "https://example.com"
        manager.addToHistory(url)

        manager.removeFromHistory(url)

        XCTAssertFalse(manager.history.contains(url))
    }

    func testClearHistory() {
        manager.addToHistory("https://example1.com")
        manager.addToHistory("https://example2.com")
        manager.addToHistory("https://example3.com")

        manager.clearHistory()

        XCTAssertTrue(manager.history.isEmpty)
    }

    // MARK: - Filtered History Tests

    func testFilteredHistoryWithEmptyQuery() {
        manager.addToHistory("https://apple.com")
        manager.addToHistory("https://google.com")

        let filtered = manager.filteredHistory(query: "")

        XCTAssertEqual(filtered.count, manager.history.count)
    }

    func testFilteredHistoryMatchesQuery() {
        manager.addToHistory("https://apple.com")
        manager.addToHistory("https://google.com")
        manager.addToHistory("https://microsoft.com")

        let filtered = manager.filteredHistory(query: "google")

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first, "https://google.com")
    }

    func testFilteredHistoryCaseInsensitive() {
        manager.addToHistory("https://Apple.com")

        let filtered = manager.filteredHistory(query: "apple")

        XCTAssertEqual(filtered.count, 1)
    }

    func testFilteredHistoryNoMatches() {
        manager.addToHistory("https://apple.com")
        manager.addToHistory("https://google.com")

        let filtered = manager.filteredHistory(query: "microsoft")

        XCTAssertTrue(filtered.isEmpty)
    }

    func testFilteredHistoryPartialMatch() {
        manager.addToHistory("https://developer.apple.com")
        manager.addToHistory("https://support.apple.com")
        manager.addToHistory("https://google.com")

        let filtered = manager.filteredHistory(query: "apple")

        XCTAssertEqual(filtered.count, 2)
    }

    // MARK: - Singleton Tests

    func testSharedInstanceExists() {
        XCTAssertNotNil(URLStorageManager.shared)
    }

    func testSharedInstanceIsSingleton() {
        let manager1 = URLStorageManager.shared
        let manager2 = URLStorageManager.shared

        XCTAssertTrue(manager1 === manager2)
    }
}
