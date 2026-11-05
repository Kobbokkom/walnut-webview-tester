//
//  DevToolsOverlayState.swift
//  wina
//
//  Created by Claude on 2/3/26.
//

import SwiftUI

enum DevToolsOverlay: String, Hashable, CaseIterable {
    case console
    case network
    case storage
    case performance
    case editor
    case accessibility
    case snippets
    case searchText

    var menuItem: DevToolsMenuItem? {
        DevToolsMenuItem(rawValue: self == .editor ? "sources" : rawValue)
    }
}

@Observable
final class DevToolsOverlayState {
    private(set) var active: Set<DevToolsOverlay> = []
    var isDocked = false

    var selectedTool: DevToolsOverlay? {
        DevToolsOverlay.allCases.first { $0 != .searchText && active.contains($0) }
    }

    func dockedTools(in order: [DevToolsMenuItem]) -> [DevToolsOverlay] {
        var tools = order.compactMap { item in DevToolsOverlay.allCases.first { $0.menuItem == item } }
        if let selectedTool, !tools.contains(selectedTool) {
            tools.append(selectedTool)
        }
        return tools
    }

    func open(_ overlay: DevToolsOverlay) {
        if overlay != .searchText {
            active = active.intersection([.searchText])
        }
        active.insert(overlay)
    }

    func close(_ overlay: DevToolsOverlay) {
        active.remove(overlay)
    }

    func toggle(_ overlay: DevToolsOverlay) {
        if active.contains(overlay) {
            active.remove(overlay)
        } else {
            open(overlay)
        }
    }

    func closeAll() {
        active.removeAll()
    }

    func isOpen(_ overlay: DevToolsOverlay) -> Bool {
        active.contains(overlay)
    }

    func presentationBinding(for overlay: DevToolsOverlay) -> Binding<Bool> {
        Binding(
            get: { !self.isDocked && self.isOpen(overlay) },
            set: { isPresented in
                guard !self.isDocked else { return }
                if isPresented {
                    self.open(overlay)
                } else {
                    self.close(overlay)
                }
            }
        )
    }

    func binding(for overlay: DevToolsOverlay) -> Binding<Bool> {
        Binding(
            get: { self.active.contains(overlay) },
            set: { $0 ? self.open(overlay) : self.close(overlay) }
        )
    }
}
