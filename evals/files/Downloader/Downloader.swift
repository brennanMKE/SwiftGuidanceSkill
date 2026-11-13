import Foundation

final class Downloader: Sendable {
    /// Streams chunks into a temporary file and returns its URL.
    func download(chunks: AsyncThrowingStream<Data, Error>) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)

        return try await withTaskCancellationHandler {
            for try await chunk in chunks {
                try handle.write(contentsOf: chunk)
            }
            try handle.close()
            return destination
        } onCancel: {
            // Cleanup: runs after the download stops because the task was cancelled.
            try? handle.close()
            try? FileManager.default.removeItem(at: destination)
        }
    }
}

@MainActor
final class DownloadController {
    let downloader = Downloader()

    func start(_ chunks: AsyncThrowingStream<Data, Error>) {
        // Must keep this Task in a property, otherwise it is deallocated
        // and the download gets cancelled as soon as start() returns.
        Task {
            let url = try await downloader.download(chunks: chunks)
            print("Saved to \(url.path)")
        }
    }
}
