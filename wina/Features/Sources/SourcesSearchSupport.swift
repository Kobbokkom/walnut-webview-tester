//
//  SourcesSearchSupport.swift
//  wina
//
//  Search UI components for Sources panel.
//

import SwiftUI

// MARK: - Search Match Count Badge

struct SearchMatchCountBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.1), in: Capsule())
    }
}

// MARK: - Search Navigation Buttons

struct SearchNavigationButtons: View {
    let onPrevious: () -> Void
    let onNext: () -> Void
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)

            Button(action: onNext) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
        }
        .foregroundStyle(isDisabled ? .tertiary : .primary)
    }
}

// MARK: - Sources Error View

struct SourcesErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - Sources Empty View

struct SourcesEmptyView: View {
    let message: LocalizedStringKey

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 12) {
                    Spacer(minLength: 0)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(width: geometry.size.width)
                .frame(minHeight: geometry.size.height)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }
}
