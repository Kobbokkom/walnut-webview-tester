//
//  ResourceDetailView.swift
//  wina
//
//  Detail view for a single resource entry showing timing breakdown.
//

import SwiftUI

// MARK: - Resource Detail View

struct ResourceDetailView: View {
    let resource: ResourceEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if resource.isCrossOriginRestricted {
                        SecurityRestrictionBanner(type: .crossOriginTiming)
                    }
                    overviewSection
                    timingSection
                    sizeSection
                    urlSection
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(Text(verbatim: "Resource Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Overview Section

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Overview")

            VStack(spacing: 0) {
                detailRow("Type", value: resource.initiatorType.displayName, icon: resource.initiatorType.icon, color: resource.initiatorType.color)
                Divider().padding(.leading, 40)
                detailRow("Duration", value: resource.displayDuration, icon: "clock")
                Divider().padding(.leading, 40)
                detailRow("Size", value: resource.displaySize, icon: "arrow.down.circle")
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Timing Section

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Timing Breakdown")

            VStack(spacing: 0) {
                // Only show detailed timing rows if not cross-origin restricted
                if !resource.isCrossOriginRestricted {
                    timingRow("DNS Lookup", time: resource.dnsTime, color: .cyan)
                    Divider().padding(.leading, 40)
                    timingRow("TCP Connect", time: resource.tcpTime, color: .blue)
                    Divider().padding(.leading, 40)
                    timingRow("TLS Handshake", time: resource.tlsTime, color: .purple)
                    Divider().padding(.leading, 40)
                    timingRow("Request", time: resource.requestTime, color: .green)
                    Divider().padding(.leading, 40)
                    timingRow("Response", time: resource.responseTime, color: .orange)
                    Divider().padding(.leading, 40)
                }
                timingRow("Total", time: resource.duration, color: .primary, isTotal: true)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))

            // Timing waterfall (only show if detailed timing available)
            if resource.duration > 0 && !resource.isCrossOriginRestricted {
                timingWaterfall
            }
        }
    }

    // MARK: - Size Section

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Size")

            VStack(spacing: 0) {
                sizeRow("Transfer Size", bytes: resource.transferSize)
                Divider().padding(.leading, 40)
                sizeRow("Encoded Size", bytes: resource.encodedBodySize)
                Divider().padding(.leading, 40)
                sizeRow("Decoded Size", bytes: resource.decodedBodySize)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - URL Section

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("URL")

            VStack(alignment: .leading, spacing: 8) {
                Text(resource.name)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

                HStack {
                    Spacer()
                    CopyButton(text: resource.name)
                }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Timing Waterfall

    @ViewBuilder
    private var timingWaterfall: some View {
        let total = resource.duration
        let phases: [(String, Double, Color)] = [
            ("DNS", resource.dnsTime, .cyan),
            ("TCP", resource.tcpTime, .blue),
            ("TLS", resource.tlsTime, .purple),
            ("Req", resource.requestTime, .green),
            ("Res", resource.responseTime, .orange)
        ].filter { $0.1 > 0 }

        if total > 0 {
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(phases, id: \.0) { phase in
                            let width = max(2, geo.size.width * (phase.1 / total))
                            Rectangle()
                                .fill(phase.2)
                                .frame(width: width)
                        }
                    }
                }
                .frame(height: 8)
                .clipShape(Capsule())

                // Legend
                HStack(spacing: 12) {
                    ForEach(phases, id: \.0) { phase in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(phase.2)
                                .frame(width: 6, height: 6)
                            Text(phase.0)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Helper Views

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.leading, 12)
    }

    private func detailRow(_ label: LocalizedStringKey, value: String, icon: String, color: Color = .secondary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func timingRow(_ label: LocalizedStringKey, time: Double, color: Color, isTotal: Bool = false) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(time > 0 ? color : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
                .padding(.leading, 8)
            Text(label)
                .font(isTotal ? .subheadline.bold() : .subheadline)
            Spacer()
            Text(formatTime(time))
                .font(.system(size: 13, weight: isTotal ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(time > 0 ? (isTotal ? .primary : .secondary) : .tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func sizeRow(_ label: LocalizedStringKey, bytes: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
            Spacer()
            if bytes > 0 {
                Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text("—")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func formatTime(_ ms: Double) -> String {
        if ms <= 0 {
            return "—"
        } else if ms < 1 {
            return "<1ms"
        } else if ms < 1000 {
            return String(format: "%.1fms", ms)
        } else {
            return String(format: "%.2fs", ms / 1000)
        }
    }
}

#Preview {
    ResourceDetailView(resource: ResourceEntry(
        id: UUID(),
        name: "https://cdn.example.com/images/hero-banner.png",
        initiatorType: .img,
        startTime: 100,
        duration: 350,
        transferSize: 125_000,
        encodedBodySize: 125_000,
        decodedBodySize: 450_000,
        dnsTime: 15,
        tcpTime: 25,
        tlsTime: 20,
        requestTime: 40,
        responseTime: 250,
        timestamp: Date()
    ))
}
