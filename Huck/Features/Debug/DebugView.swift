//
//  DebugView.swift
//  Huck
//
//  Created by James Asbury on 10/3/26.
//

import SwiftUI

/// The Debug tab, shown when debug mode is on: live request counts per API,
/// broken down by endpoint, to see where the app's traffic actually goes, and
/// the crash and performance reports MetricKit has delivered.
struct DebugView: View {
    private let metrics = APIMetrics.shared
    private let diagnostics = DiagnosticsStore.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Total Requests") {
                        countText(metrics.total)
                    }
                } footer: {
                    Text("Counting since \(metrics.countingSince.formatted(date: .omitted, time: .standard))")
                }

                ForEach(APISource.allCases) { source in
                    Section {
                        LabeledContent {
                            countText(metrics.total(for: source))
                        } label: {
                            Label(source.title, systemImage: source.systemImage)
                                .fontWeight(.semibold)
                        }
                        ForEach(metrics.endpoints(for: source), id: \.name) { endpoint in
                            LabeledContent(endpoint.name) {
                                countText(endpoint.count)
                            }
                            .padding(.leading)
                        }
                    }
                }

                diagnosticsSection
            }
            .navigationTitle("Debug")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Reset", systemImage: "arrow.counterclockwise") {
                        metrics.reset()
                    }
                }
            }
        }
    }

    /// Each saved report, shared as its JSON when tapped.
    private var diagnosticsSection: some View {
        Section {
            if diagnostics.reports.isEmpty {
                Text("No reports yet")
                    .foregroundStyle(.secondary)
            }
            ForEach(diagnostics.reports) { report in
                ShareLink(item: diagnostics.fileURL(for: report)) {
                    diagnosticRow(report)
                }
            }
            .onDelete { diagnostics.delete(at: $0) }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Crashes, hangs, and daily performance reports from MetricKit, kept on this device. They arrive only on a physical device; to test, run from Xcode and choose Debug › MetricKit › Simulate MetricKit Payloads.")
        }
    }

    private func diagnosticRow(_ report: SavedDiagnostic) -> some View {
        Label {
            VStack(alignment: .leading) {
                Text(report.summary)
                    .lineLimit(3)
                Text([report.receivedAt.formatted(date: .abbreviated, time: .shortened), report.appVersion]
                    .compactMap(\.self)
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: report.kind.systemImage)
                .foregroundStyle(report.kind == .crash || report.kind == .memoryException ? .red : .secondary)
        }
    }

    private func countText(_ count: Int) -> some View {
        Text(count, format: .number)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(count)))
            .animation(.default, value: count)
    }
}

#Preview {
    DebugView()
}
