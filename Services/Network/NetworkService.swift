import Foundation

// MARK: - Network Errors

enum NetworkError: Error {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, Data?)
    case decoding(DecodingError)
    case transport(Error)
}

// MARK: - Network Service Protocol (DI-friendly)

protocol NetworkServiceProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func request<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T
}

// MARK: - Network Service

/// Base network layer using async/await and URLSession.
/// No force unwrapping; DI-ready via protocol.
final class NetworkService: NetworkServiceProtocol, @unchecked Sendable {

    private let session: URLSession
    private let decoder: JSONDecoder

    init(
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.session = session
        self.decoder = decoder
    }

    /// Raw data + response. Caller validates status.
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw NetworkError.transport(error)
        }
    }

    /// Fetch and decode JSON. Validates HTTP 200..<300; throws on failure.
    func request<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            throw NetworkError.httpStatus(http.statusCode, data)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch let decodingError as DecodingError {
            throw NetworkError.decoding(decodingError)
        }
    }
}
