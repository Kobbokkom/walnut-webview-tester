//
//  PerformanceHelperViews.swift
//  wina
//
//  Helper views for Performance panel.
//

import SwiftUI

// MARK: - Core Vital Card (Bento Grid Item)

struct CoreVitalCard: View {
    let label: String
    let value: String
    let rating: PerformanceRating
    let description: LocalizedStringKey

    var body: some View {
        VStack(spacing: 6) {
            Text(verbatim: label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(rating.color)

            Image(systemName: rating.icon)
                .font(.caption)
                .foregroundStyle(rating.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(rating.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Metric Row

struct MetricRow: View {
    let label: LocalizedStringResource
    let value: Double
    let rating: PerformanceRating

    var body: some View {
        HStack {
            Image(systemName: rating.icon)
                .foregroundStyle(rating.color)
                .frame(width: 20)

            Text(label)

            Spacer()

            Text(formatTime(value))
                .foregroundStyle(rating.color)
                .monospacedDigit()
        }
        .padding(.vertical, 8)
    }

    private func formatTime(_ ms: Double) -> String {
        if ms >= 1000 {
            return String(format: "%.2fs", ms / 1000)
        }
        return String(format: "%.0fms", ms)
    }
}

// MARK: - Resource Detail Row (Expandable List Item)

struct ResourceDetailRow: View {
    let resource: ResourceTiming

    var body: some View {
        HStack(spacing: 8) {
            Text(resource.shortName)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Text(formatTime(resource.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)

            Text(resource.displaySize > 0 ? ByteFormatter.format(resource.displaySize) : "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
    }

    private func formatTime(_ ms: Double) -> String {
        if ms >= 1000 {
            return String(format: "%.2fs", ms / 1000)
        }
        return String(format: "%.0fms", ms)
    }

}

// MARK: - Timing Breakdown Row

struct TimingBreakdownRow: View {
    let label: LocalizedStringResource
    let value: Double
    let total: Double

    var body: some View {
        HStack {
            Text(label)

            Spacer()

            // Progress bar
            GeometryReader { geometry in
                let width = geometry.size.width
                let barWidth = total > 0 ? (value / total) * width : 0

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 8)
                        .clipShape(Capsule())

                    Rectangle()
                        .fill(.blue)
                        .frame(width: barWidth, height: 8)
                        .clipShape(Capsule())
                }
            }
            .frame(width: 80, height: 8)

            Text(formatTime(value))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
    }

    private func formatTime(_ ms: Double) -> String {
        if ms >= 1000 {
            return String(format: "%.2fs", ms / 1000)
        }
        return String(format: "%.0fms", ms)
    }
}

// MARK: - Timeline Row

struct TimelineRow: View {
    let label: LocalizedStringResource
    let time: Double

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(formatTime(time))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func formatTime(_ ms: Double) -> String {
        if ms >= 1000 {
            return String(format: "%.2fs", ms / 1000)
        }
        return String(format: "%.0fms", ms)
    }
}
