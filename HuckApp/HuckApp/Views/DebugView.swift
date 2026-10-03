//
//  DebugView.swift
//  HuckApp
//
//  Created by James Asbury on 10/3/26.
//

import SwiftUI

/// The Debug tab, shown when debug mode is on: live request counts per API,
/// broken down by endpoint, to see where the app's traffic actually goes.
struct DebugView: View {
    private let metrics = APIMetrics.shared

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
