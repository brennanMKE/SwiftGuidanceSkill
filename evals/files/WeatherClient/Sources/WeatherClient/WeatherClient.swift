import Foundation
internal import HTTPCore   // was `import HTTPCore`

public struct Forecast: Sendable, Decodable {
    public let high: Double
    public let low: Double
}

public struct WeatherClient: Sendable {
    private let http = HTTPClient()

    public init() {}

    public func forecast(for city: String) async throws -> Forecast {
        let url = URL(string: "https://example.com/forecast?city=\(city)")!
        let response = try await http.get(url)
        return try JSONDecoder().decode(Forecast.self, from: response.body)
    }
}
