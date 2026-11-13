import Foundation
import Observation

struct Row: Sendable {
    let region: String
    let amount: Double
}

@Observable
final class ReportViewModel {
    var summary = ""
    var isWorking = false

    func refresh(rows: [Row]) async {
        isWorking = true
        summary = await ReportBuilder.summarize(rows)
        isWorking = false
    }
}

enum ReportBuilder {
    // CPU-heavy: groups and sorts hundreds of thousands of rows.
    nonisolated static func summarize(_ rows: [Row]) async -> String {
        var totals: [String: Double] = [:]
        for row in rows {
            totals[row.region, default: 0] += row.amount
        }
        return totals
            .sorted { $0.value > $1.value }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }
}
