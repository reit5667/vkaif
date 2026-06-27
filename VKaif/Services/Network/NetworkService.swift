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
/// Логирует запросы/ответы через AppLogger при переданном logger.
final class NetworkService: NetworkServiceProtocol, @unchecked Sendable {

    private let session: URLSession
    private let decoder: JSONDecoder
    private let logger: (any AppLogging)?

    private static let networkCategory = "Network"

    init(
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        logger: (any AppLogging)? = AppLogger.shared
    ) {
        self.session = session
        self.decoder = decoder
        self.logger = logger
    }

    /// Raw data + response. Caller validates status.
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        logRequest(request)
        do {
            let (data, response) = try await session.data(for: request)
            logResponse(response, data: data, for: request)
            return (data, response)
        } catch {
            logger?.error(Self.networkCategory, "data(for:) failed", error: error)
            throw NetworkError.transport(error)
        }
    }

    /// Fetch and decode JSON. Validates HTTP 200..<300; throws on failure.
    func request<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        logRequest(request)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger?.error(Self.networkCategory, "request failed", error: error)
            throw NetworkError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            logger?.error(Self.networkCategory, "invalid response (not HTTPURLResponse)")
            throw NetworkError.invalidResponse
        }

        logResponse(http, data: data, for: request)

        guard (200 ..< 300).contains(http.statusCode) else {
            logger?.error(Self.networkCategory, "HTTP \(http.statusCode)", error: nil)
            throw NetworkError.httpStatus(http.statusCode, data)
        }

        do {
            let decoded = try decoder.decode(T.self, from: data)
            logger?.debug(Self.networkCategory, "decoded \(String(describing: type))")
            return decoded
        } catch let decodingError as DecodingError {
            logger?.error(Self.networkCategory, "decoding failed", error: decodingError)
            throw NetworkError.decoding(decodingError)
        }
    }

    private func logRequest(_ request: URLRequest) {
        let url = request.url?.absoluteString ?? "nil"
        let method = request.httpMethod ?? "?"
        logger?.debug(Self.networkCategory, "→ \(method) \(url)")
    }

    private func logResponse(_ response: URLResponse, data: Data, for request: URLRequest) {
        guard let http = response as? HTTPURLResponse else { return }
        let status = http.statusCode
        let len = data.count
        logger?.info(Self.networkCategory, "← \(status) \(len) bytes")
    }

    private func logResponse(_ http: HTTPURLResponse, data: Data, for request: URLRequest) {
        let status = http.statusCode
        let len = data.count
        logger?.info(Self.networkCategory, "← \(status) \(len) bytes")
    }
}
