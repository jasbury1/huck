//
//  DiagnosticsStore.swift
//  Huck
//
//  Created by James Asbury on 11/8/26.
//

import Foundation
import MetricKit
import OSLog

/// A MetricKit report saved on this device, as listed on the debug screen. The
/// report itself is in its own file; this is the part worth listing.
nonisolated struct SavedDiagnostic: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case crash
        case hang
        case cpuException
        case diskWriteException
        case slowLaunch
        case memoryException
        case dailyMetrics
        /// A diagnostic kind added to MetricKit after this was written.
        case other

        var systemImage: String {
            switch self {
            case .crash: "xmark.octagon"
            case .hang: "hourglass"
            case .cpuException: "cpu"
            case .diskWriteException: "internaldrive"
            case .slowLaunch: "timer"
            case .memoryException: "memorychip"
            case .dailyMetrics: "chart.bar"
            case .other: "questionmark.circle"
            }
        }
    }

    let id: UUID
    let kind: Kind
    let receivedAt: Date
    let summary: String
    /// The version and build the report came from, when MetricKit says.
    let appVersion: String?

    var fileName: String { "\(id.uuidString).json" }
}

/// Receives MetricKit's reports for the app's lifetime and keeps the most
/// recent on disk.
///
/// This is the app's only record of a crash or hang that happened away from
/// Xcode: on a personal signing team there's no Organizer data, and MetricKit
/// hands its reports to the app and nowhere else. Each one is logged when it
/// arrives and saved whole as JSON, call stacks included, so it can be shared
/// from the debug screen and symbolicated against the build's dSYM.
///
/// App-wide like `APIMetrics`, and collected whether or not debug mode is on,
/// so turning it on shows everything since install.
@MainActor
@Observable
final class DiagnosticsStore {
    static let shared = DiagnosticsStore()

    /// How many reports are kept. Diagnostics are rare and a daily metrics
    /// report comes at most once a day, so this spans weeks to months.
    static let maxReports = 50

    /// Saved reports, newest first.
    private(set) var reports: [SavedDiagnostic]

    /// MetricKit asks for one manager per app: two iterating the same sequence
    /// would each receive only some of the reports.
    @ObservationIgnored private let manager = MetricManager()
    @ObservationIgnored private var isObserving = false

    private init() {
        reports = JSONFile.load([SavedDiagnostic].self, from: Self.indexURL, name: "diagnostics index") ?? []
    }

    /// Receives reports for as long as the calling task runs. Start it once, at
    /// the app's root; a second call while one is running returns at once, so
    /// the reports aren't split between them.
    func observe() async {
        guard !isObserving else { return }
        isObserving = true
        defer { isObserving = false }

        async let diagnostics: Void = observeDiagnosticReports()
        async let metrics: Void = observeMetricReports()
        _ = await (diagnostics, metrics)
    }

    /// Where a saved report's JSON is, for sharing.
    func fileURL(for report: SavedDiagnostic) -> URL {
        Self.directory.appending(path: report.fileName)
    }

    func delete(at offsets: IndexSet) {
        for report in offsets.map({ reports[$0] }) {
            removeFile(of: report)
        }
        reports = reports.indices.filter { !offsets.contains($0) }.map { reports[$0] }
        saveIndex()
    }

    // MARK: - Receiving

    private func observeDiagnosticReports() async {
        for await report in manager.diagnosticReports {
            let (kind, summary) = Self.describe(report.result)
            let environment = report.environment
            let version = "\(environment.applicationVersion) (\(environment.applicationBuildVersion))"
            switch kind {
            case .crash, .memoryException:
                Logger.diagnostics.error("MetricKit reported a \(kind.rawValue, privacy: .public) in \(version, privacy: .public): \(summary)")
            default:
                Logger.diagnostics.notice("MetricKit reported a \(kind.rawValue, privacy: .public) in \(version, privacy: .public): \(summary)")
            }
            save(report, kind: kind, summary: summary, appVersion: version)
        }
    }

    private func observeMetricReports() async {
        for await report in manager.metricReports {
            let range = report.timeRange
            let summary = "Daily metrics, \(range.start.formatted(date: .abbreviated, time: .shortened)) – \(range.end.formatted(date: .abbreviated, time: .shortened))"
            Logger.diagnostics.notice("MetricKit delivered daily metrics for \(range.start.formatted(), privacy: .public) – \(range.end.formatted(), privacy: .public)")
            save(report, kind: .dailyMetrics, summary: summary, appVersion: report.environment?.applicationBuildVersion)
        }
    }

    /// A diagnostic's kind and a one-line account of it.
    private static func describe(_ result: DiagnosticResult) -> (SavedDiagnostic.Kind, String) {
        switch result {
        case let .crash(diagnostic):
            var details: [String] = []
            if let reason = diagnostic.exceptionReason {
                details.append(reason.composedMessage)
            }
            if let signal = diagnostic.signal {
                details.append("signal \(signal)")
            }
            if let exceptionType = diagnostic.exceptionType {
                details.append("exception type \(exceptionType)")
            }
            return (.crash, details.isEmpty ? "Crash" : "Crash: \(details.joined(separator: ", "))")
        case let .hang(diagnostic):
            return (.hang, "Hang of \(diagnostic.hangDuration.formatted())")
        case let .cpuException(diagnostic):
            return (.cpuException, "CPU exception: \(diagnostic.totalCPUTime.formatted()) of CPU time")
        case let .diskWriteException(diagnostic):
            return (.diskWriteException, "Disk write exception: \(diagnostic.totalBytesWritten.formatted()) written")
        case let .appLaunch(diagnostic):
            return (.slowLaunch, "Slow launch of \(diagnostic.launchDuration.formatted())")
        case .memoryException:
            return (.memoryException, "Terminated for exceeding the memory limit")
        @unknown default:
            return (.other, "Unrecognized diagnostic")
        }
    }

    // MARK: - Storage

    private static var directory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Diagnostics", directoryHint: .isDirectory)
    }

    private static var indexURL: URL {
        directory.appending(path: "index.json")
    }

    /// Saves a report and lists it, dropping the oldest past `maxReports`.
    private func save(_ report: some Encodable, kind: SavedDiagnostic.Kind, summary: String, appVersion: String?) {
        let saved = SavedDiagnostic(id: UUID(), kind: kind, receivedAt: .now, summary: summary, appVersion: appVersion)
        JSONFile.save(report, to: fileURL(for: saved), name: "\(kind.rawValue) report")
        reports.insert(saved, at: 0)
        while reports.count > Self.maxReports {
            removeFile(of: reports.removeLast())
        }
        saveIndex()
    }

    private func saveIndex() {
        JSONFile.save(reports, to: Self.indexURL, name: "diagnostics index")
    }

    private func removeFile(of report: SavedDiagnostic) {
        do {
            try FileManager.default.removeItem(at: fileURL(for: report))
        } catch {
            Logger.persistence.error("Couldn't remove diagnostic \(report.fileName, privacy: .public): \(error, privacy: .public)")
        }
    }
}
