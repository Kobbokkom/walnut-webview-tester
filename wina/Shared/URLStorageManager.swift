//
//  URLStorageManager.swift
//  wina
//
//  Shared storage manager for bookmarks and history.
//

import Foundation
import SwiftUI

@Observable
final class URLStorageManager {
    static let shared = URLStorageManager()

    // MARK: - Published State

    private(set) var bookmarks: [String] = []
    private(set) var history: [String] = []

    // MARK: - AppStorage Keys

    private let bookmarksKey = "bookmarkedURLs"
    private let historyKey = "recentURLs"
    private let maxHistoryCount = 50

    // MARK: - Init

    private init() {
        loadFromStorage()
    }

    // MARK: - Load

    private func loadFromStorage() {
        // Load bookmarks
        if let data = UserDefaults.standard.data(forKey: bookmarksKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            bookmarks = decoded
        }

        // Load history
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            history = decoded
        }
    }

    // MARK: - Bookmarks

    func addBookmark(_ url: String) {
        guard !url.isEmpty, !bookmarks.contains(url) else { return }
        bookmarks.insert(url, at: 0)
        saveBookmarks()
    }

    func removeBookmark(_ url: String) {
        bookmarks.removeAll { $0 == url }
        saveBookmarks()
    }

    func isBookmarked(_ url: String) -> Bool {
        bookmarks.contains(url)
    }

    func toggleBookmark(_ url: String) {
        if isBookmarked(url) {
            removeBookmark(url)
        } else {
            addBookmark(url)
        }
    }

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        }
    }

    // MARK: - History

    func addToHistory(_ url: String) {
        guard !url.isEmpty else { return }

        // Remove if exists (to move to top)
        history.removeAll { $0 == url }

        // Add to top
        history.insert(url, at: 0)

        // Limit history count
        if history.count > maxHistoryCount {
            history = Array(history.prefix(maxHistoryCount))
        }

        saveHistory()
    }

    func removeFromHistory(_ url: String) {
        history.removeAll { $0 == url }
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    // MARK: - Filtered History

    func filteredHistory(query: String) -> [String] {
        if query.isEmpty {
            return history
        }
        return history.filter { $0.localizedCaseInsensitiveContains(query) }
    }
}
