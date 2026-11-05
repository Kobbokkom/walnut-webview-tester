//
//  BarConstants.swift
//  wina
//
//  Centralized constants for overlay menu bars and WebView layout.
//

import SwiftUI

enum BarConstants {
    // MARK: - Bar Dimensions

    /// Height of both top and bottom bars
    static let barHeight: CGFloat = 64

    /// Horizontal padding around bars
    static let horizontalPadding: CGFloat = 8

    // MARK: - Safe Area Handling

    /// How much of safe area bottom the bottom bar extends into (0 = none, 1 = full)
    /// At 0.5, bottom bar goes 50% into safe area (sits nicely above home indicator)
    static let bottomBarSafeAreaRatio: CGFloat = 0.5

    // MARK: - WebView Layout

    /// WebView vertical offset ratio to balance gaps between top and bottom bars
    /// Higher value = WebView moves up more, creating more bottom gap
    static let webViewOffsetRatio: CGFloat = 0.375

    /// Additional spacing beyond bar heights for "App" preset calculation
    /// Accounts for visual gaps between bars and WebView
    static let additionalSpacing: CGFloat = 64

    /// Total UI height used for "App" preset WebView size calculation
    /// Formula: top bar + bottom bar + additional spacing
    static var totalUIHeight: CGFloat {
        barHeight * 2 + additionalSpacing
    }

    /// Calculates the "App" preset height ratio for WebView
    /// Returns the height ratio that fits the WebView within the app's UI bars
    static func appContainerHeightRatio(for screenHeight: CGFloat) -> Double {
        guard screenHeight > 0 else { return 0.25 }
        return min(1.0, max(0.25, 1.0 - (totalUIHeight / screenHeight)))
    }

    static func heightRatioAfterResize(
        widthRatio: Double, heightRatio: Double, from oldHeight: CGFloat, to newHeight: CGFloat
    ) -> Double {
        guard oldHeight > 0, newHeight > 0,
              widthRatio == 1,
              heightRatio == appContainerHeightRatio(for: oldHeight) else { return heightRatio }
        return appContainerHeightRatio(for: newHeight)
    }

    // MARK: - Sheet Presentation

    /// Standard sheet detents with compact option
    static let sheetDetents: Set<PresentationDetent> = [.fraction(0.35), .medium, .large]

    /// Default sheet detent when opening
    static let defaultSheetDetent: PresentationDetent = .medium
}
