//
//  NetworkTimingView.swift
//  wina
//
//  Network request timing display with visual representation.
//  Shows total duration and timing breakdown within JavaScript API constraints.
//

import SwiftUI

// MARK: - Network Timing View

struct NetworkTimingView: View {
    let request: NetworkRequest
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.blue)

                    Text("Timing")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .padding(.bottom, 4)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // Total duration
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Duration")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text(request.durationText)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    Divider()

                    // Timing breakdown (within JavaScript limitations)
                    if let duration = request.duration, duration > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Timing Breakdown")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)

                            // Visual timeline bar
                            TimingVisualizationBar(duration: duration)

                            // Timing phases (JavaScript limitations noted)
                            VStack(alignment: .leading, spacing: 6) {
                                TimingPhaseRow(
                                    label: "Request → Response",
                                    duration: duration,
                                    color: .blue,
                                    icon: "arrow.right"
                                )
                            }
                        }

                        // Note about limitations
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 9))
                            Text("JavaScript API limitation: DNS, TCP, SSL times not available")
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
                    } else if request.isPending {
                        // Request still in progress
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Waiting for response...")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("Timing not available")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Timing Visualization Bar

struct TimingVisualizationBar: View {
    let duration: TimeInterval

    private var durationInMs: Int {
        Int(duration * 1000)
    }

    private var barWidth: CGFloat {
        min(CGFloat(durationInMs) / 5.0, 280)  // Max width 280pt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Main timing bar
            HStack(spacing: 0) {
                Capsule()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .cyan]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: barWidth, height: 20)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Scale markers
            HStack(spacing: 0) {
                Text("0ms")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Spacer()

                Text("\(durationInMs)ms")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Timing Phase Row

struct TimingPhaseRow: View {
    let label: LocalizedStringKey
    let duration: TimeInterval
    let color: Color
    let icon: String

    private var durationText: String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else {
            return String(format: "%.2fs", duration)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)

                Text(durationText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Percentage indicator
            Text(String(format: "%.0f%%", 100.0))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Timing Statistics View

struct TimingStatisticsView: View {
    let requests: [NetworkRequest]

    private var averageDuration: TimeInterval {
        guard !requests.isEmpty else { return 0 }
        let total = requests.compactMap { $0.duration }.reduce(0, +)
        return total / Double(requests.count)
    }

    private var longestDuration: TimeInterval {
        requests.compactMap { $0.duration }.max() ?? 0
    }

    private var shortestDuration: TimeInterval {
        let durations = requests.compactMap { $0.duration }
        return durations.min() ?? 0
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        if interval < 1 {
            return String(format: "%.0fms", interval * 1000)
        } else {
            return String(format: "%.2fs", interval)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timing Statistics")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                StatisticRow(
                    label: "Average",
                    value: formatDuration(averageDuration),
                    icon: "chart.bar",
                    color: .blue
                )

                StatisticRow(
                    label: "Longest",
                    value: formatDuration(longestDuration),
                    icon: "arrow.up",
                    color: .red
                )

                StatisticRow(
                    label: "Shortest",
                    value: formatDuration(shortestDuration),
                    icon: "arrow.down",
                    color: .green
                )
            }
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Statistic Row

struct StatisticRow: View {
    let label: LocalizedStringKey
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()

            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    VStack(spacing: 20) {
        // Example timing view
        let exampleRequest = NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "https://api.example.com/data",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: Date().addingTimeInterval(-1.5),
            pageIsSecure: true,
            status: 200,
            statusText: "OK",
            responseHeaders: nil,
            responseBodyPreview: "{}",
            endTime: Date(),
            requestType: .fetch
        )

        NetworkTimingView(request: exampleRequest)

        Divider()

        // Statistics example
        let requests = [
            exampleRequest,
            NetworkRequest(
                id: UUID(),
                method: "POST",
                url: "https://api.example.com/submit",
                requestHeaders: nil,
                requestBodyPreview: nil,
                startTime: Date().addingTimeInterval(-0.8),
                pageIsSecure: true,
                status: 201,
                statusText: "Created",
                responseHeaders: nil,
                responseBodyPreview: "{}",
                endTime: Date(),
                requestType: .fetch
            )
        ]

        TimingStatisticsView(requests: requests)

        Spacer()
    }
    .padding()
}
