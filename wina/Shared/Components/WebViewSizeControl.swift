//
//  WebViewSizeControl.swift
//  wina
//
//  Created by Claude on 12/13/25.
//

import SwiftUI

// MARK: - WebView Size Control

struct WebViewSizeControl: View {
    @Binding var widthRatio: Double
    @Binding var heightRatio: Double

    private var appContainerHeightRatio: Double {
        BarConstants.appContainerHeightRatio(for: containerSize.height)
    }

    @Environment(\.webViewContainerSize) private var containerSize

    private var currentWidth: Int {
        Int(containerSize.width * widthRatio)
    }

    private var currentHeight: Int {
        Int(containerSize.height * heightRatio)
    }

    private var isAppContainerSelected: Bool {
        widthRatio == 1 && heightRatio == appContainerHeightRatio
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                PresetButton(label: "100%", isSelected: widthRatio == 1.0 && heightRatio == 1.0) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        widthRatio = 1.0
                        heightRatio = 1.0
                    }
                }
                PresetButton(label: "App", isSelected: isAppContainerSelected) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        widthRatio = 1.0
                        heightRatio = appContainerHeightRatio
                    }
                }
                PresetButton(label: "75%", isSelected: widthRatio == 0.75 && heightRatio == 0.75) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        widthRatio = 0.75
                        heightRatio = 0.75
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Width")
                        .font(.subheadline)
                    Spacer()
                    Text("\(currentWidth)pt")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $widthRatio, in: 0.25...1.0, step: 0.01)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Height")
                        .font(.subheadline)
                    Spacer()
                    Text("\(currentHeight)pt")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $heightRatio, in: 0.25...1.0, step: 0.01)
            }

            HStack {
                Spacer()
                Text("\(currentWidth) × \(currentHeight)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preset Button

struct PresetButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var width = 1.0
    @Previewable @State var height = 0.82
    List {
        Section("WebView Size") {
            WebViewSizeControl(widthRatio: $width, heightRatio: $height)
        }
    }
}
