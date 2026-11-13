// Xcode 27 project. Build settings: SWIFT_VERSION = 6.0,
// SWIFT_APPROACHABLE_CONCURRENCY = YES, SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
import SwiftUI
import ImageIO

@Observable
final class ThumbnailLoader {
    var thumbnails: [URL: CGImage] = [:]

    func loadAll(_ urls: [URL]) {
        for url in urls {
            Task {
                guard let data = try? Data(contentsOf: url) else { return }
                let image = await Self.decodeThumbnail(data, maxPixel: 512)
                thumbnails[url] = image
            }
        }
    }

    // Previously ran inside DispatchQueue.global(qos: .userInitiated).async { ... }
    nonisolated static func decodeThumbnail(_ data: Data, maxPixel: Int) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
