//
//  PerformanceView+Metrics.swift
//  wina
//
//  Metrics section for PerformanceView.
//

import SwiftUI

// MARK: - Metrics Section

extension PerformanceView {
    @ViewBuilder
    var metricsSection: some View {
        PerformanceSection(title: "Loading Performance") {
            VStack(spacing: 0) {
                if let fcp = performanceManager.data.firstContentfulPaint {
                    if matchesSearch("First Contentful Paint") {
                        MetricRow(
                            label: "First Contentful Paint",
                            value: fcp,
                            rating: MetricThresholds.rate(
                                fcp,
                                good: MetricThresholds.fcpGood,
                                poor: MetricThresholds.fcpPoor
                            )
                        )
                        sectionDivider
                    }
                }

                if let nav = performanceManager.data.navigation {
                    if matchesSearch("Time to First Byte") || matchesSearch("TTFB") {
                        MetricRow(
                            label: "Time to First Byte",
                            value: nav.ttfb,
                            rating: MetricThresholds.rate(
                                nav.ttfb,
                                good: MetricThresholds.ttfbGood,
                                poor: MetricThresholds.ttfbPoor
                            )
                        )
                        sectionDivider
                    }

                    if matchesSearch("DOM Content Loaded") {
                        MetricRow(
                            label: "DOM Content Loaded",
                            value: nav.domContentLoadedTime,
                            rating: MetricThresholds.rate(
                                nav.domContentLoadedTime,
                                good: MetricThresholds.dclGood,
                                poor: MetricThresholds.dclPoor
                            )
                        )
                        sectionDivider
                    }

                    if matchesSearch("Page Load") {
                        MetricRow(
                            label: "Page Load",
                            value: nav.loadEventTime,
                            rating: MetricThresholds.rate(
                                nav.loadEventTime,
                                good: MetricThresholds.lcpGood,
                                poor: MetricThresholds.lcpPoor
                            )
                        )
                    }
                }

                if performanceManager.data.tbt >= 0 {
                    if matchesSearch("Total Blocking Time") || matchesSearch("TBT") {
                        sectionDivider
                        MetricRow(
                            label: "Total Blocking Time",
                            value: performanceManager.data.tbt,
                            rating: MetricThresholds.rate(
                                performanceManager.data.tbt,
                                good: MetricThresholds.tbtGood,
                                poor: MetricThresholds.tbtPoor
                            )
                        )
                    }
                }
            }
        }

        PerformanceSection(title: "Network") {
            VStack(spacing: 0) {
                if let nav = performanceManager.data.navigation {
                    if matchesSearch("DNS") {
                        MetricRow(
                            label: "DNS Lookup",
                            value: nav.dnsTime,
                            rating: MetricThresholds.rate(
                                nav.dnsTime,
                                good: MetricThresholds.dnsGood,
                                poor: MetricThresholds.dnsPoor
                            )
                        )
                        sectionDivider
                    }

                    if matchesSearch("Connection") || matchesSearch("TCP") || matchesSearch("TLS") {
                        MetricRow(
                            label: "Connection (TCP+TLS)",
                            value: nav.connectionTime,
                            rating: MetricThresholds.rate(
                                nav.connectionTime,
                                good: MetricThresholds.connectGood,
                                poor: MetricThresholds.connectPoor
                            )
                        )
                    }

                    if nav.redirectTime > 0 && matchesSearch("Redirect") {
                        sectionDivider
                        MetricRow(
                            label: "Redirect",
                            value: nav.redirectTime,
                            rating: nav.redirectTime > 100 ? .needsImprovement : .good
                        )
                    }
                }
            }
        }

        PerformanceSection(title: "Summary") {
            VStack(spacing: 0) {
                if matchesSearch("Resources") {
                    HStack {
                        Label("Resources", systemImage: "doc.fill")
                        Spacer()
                        Text("\(performanceManager.data.totalResources)")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                    sectionDivider
                }
                if matchesSearch("Transfer") {
                    HStack {
                        Label("Total Transfer", systemImage: "arrow.down.circle.fill")
                        Spacer()
                        Text(ByteFormatter.format(performanceManager.data.totalTransferSize))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }

    @ViewBuilder
    var timingSection: some View {
        if let nav = performanceManager.data.navigation {
            PerformanceSection(title: "Navigation Breakdown") {
                VStack(spacing: 0) {
                    let breakdowns: [(LocalizedStringResource, Double)] = [
                        ("Redirect", nav.redirectTime),
                        ("DNS", nav.dnsTime),
                        ("TCP", nav.tcpTime),
                        ("TLS", nav.tlsTime),
                        ("Request", nav.requestTime),
                        ("Response", nav.responseTime),
                        ("DOM Processing", nav.domProcessingTime)
                    ]

                    ForEach(Array(breakdowns.enumerated()), id: \.offset) { index, item in
                        if matchesSearch(String(localized: item.0)) {
                            TimingBreakdownRow(label: item.0, value: item.1, total: nav.loadEventTime)
                                .padding(.vertical, 8)
                            if index < breakdowns.count - 1 {
                                sectionDivider
                            }
                        }
                    }
                }
            }

            PerformanceSection(title: "Timeline") {
                VStack(spacing: 0) {
                    if matchesSearch("TTFB") {
                        TimelineRow(label: "TTFB", time: nav.ttfb)
                            .padding(.vertical, 8)
                        sectionDivider
                    }
                    if let fcp = performanceManager.data.firstContentfulPaint, matchesSearch("FCP") {
                        TimelineRow(label: "FCP", time: fcp)
                            .padding(.vertical, 8)
                        sectionDivider
                    }
                    if matchesSearch("DOM Ready") {
                        TimelineRow(label: "DOM Ready", time: nav.domContentLoadedTime)
                            .padding(.vertical, 8)
                        sectionDivider
                    }
                    if matchesSearch("Load") {
                        TimelineRow(label: "Load", time: nav.loadEventTime)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}
