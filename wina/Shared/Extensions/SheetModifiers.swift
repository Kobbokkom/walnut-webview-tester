//
//  SheetModifiers.swift
//  wina
//
//  Reusable sheet presentation modifiers.
//

import SwiftUI

// MARK: - DevTools Sheet Modifier

struct DevToolsSheetModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var detent: PresentationDetent = BarConstants.defaultSheetDetent

    func body(content: Content) -> some View {
        content
            .presentationDetents(BarConstants.sheetDetents, selection: $detent)
            .presentationSizing(.form)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationContentInteraction(.scrolls)
            .presentationDragIndicator(.visible)
            .onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in
                detent = sizeClass == .regular ? .large : BarConstants.defaultSheetDetent
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                if detent != .large {
                    detent = .large
                }
            }
    }
}

// MARK: - Full Size Sheet Modifier

struct FullSizeSheetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .presentationDetents([.large])
            .presentationSizing(.page)
            .presentationContentInteraction(.scrolls)
            .presentationDragIndicator(.visible)
    }
}

extension View {
    /// DevTools sheet style with compact option, starts at medium detent
    func devToolsSheet() -> some View {
        modifier(DevToolsSheetModifier())
    }

    /// Full size sheet for Settings/Info, always large on both iOS and iPad
    func fullSizeSheet() -> some View {
        modifier(FullSizeSheetModifier())
    }

    /// Dismiss keyboard by resigning first responder (works in sheets)
    func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    /// Dismiss keyboard when tapping outside input fields (for use in sheets)
    /// Uses simultaneousGesture to allow button interactions to work
    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded { _ in
                hideKeyboard()
            }
        )
    }
}
