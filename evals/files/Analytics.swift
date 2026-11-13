import os
import Foundation

private let logger = Logger(subsystem: "com.example.shop", category: "Analytics")

struct Analytics {
    func trackPurchase(userID: String, sku: String, amount: Decimal, at date: Date) {
        logger.info("purchase user=\(userID) sku=\(sku) amount=\(amount) date=\(date)")
    }

    func syncBatch(_ events: [String]) {
        let signpostID = OSSignpostID(log: logger)
        os_signpost(.begin, log: logger, name: "Sync", signpostID: signpostID)
        upload(events)
        os_signpost(.end, log: logger, name: "Sync", signpostID: signpostID)
        logger.warning("synced \(events.count) events")
    }

    private func upload(_ events: [String]) {}
}
