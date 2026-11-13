import Foundation

public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data
    public init(status: Int, body: Data) { self.status = status; self.body = body }
}

public struct HTTPClient: Sendable {
    public init() {}
    public func get(_ url: URL) async throws -> HTTPResponse {
        let (data, response) = try await URLSession.shared.data(from: url)
        return HTTPResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }
}
