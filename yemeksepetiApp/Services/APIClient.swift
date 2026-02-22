import Foundation
import FirebaseAuth

// MARK: - APIConfig

enum APIConfig {
    static let baseURL = "https://massive-dalila-ertu-0c50a20b.koyeb.app/api/v1"

    static var useRecommendations: Bool {
        ProcessInfo.processInfo.environment["USE_RECOMMENDATIONS"] != "false"
    }
}

// MARK: - APIError

enum APIError: Error, LocalizedError {
    case invalidURL
    case unauthorized
    case notFound
    case serverError(Int, String)
    case decodingFailed(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Geçersiz URL"
        case .unauthorized:        return "Oturum süreniz dolmuş, lütfen tekrar giriş yapın."
        case .notFound:            return "İçerik bulunamadı."
        case .serverError(let c, let m): return "Sunucu hatası (\(c)): \(m)"
        case .decodingFailed(let e):     return "Veri çözümleme hatası: \(e)"
        case .networkError(let e):       return "Ağ hatası: \(e)"
        }
    }
}

// MARK: - APIClient

/// Merkezi HTTP istemcisi — her istekte Firebase ID token ekler.
actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 40   // Koyeb cold-start ≤ 40s
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // ── Token ─────────────────────────────────────────────────────────────────

    private func idToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw APIError.unauthorized
        }
        return try await user.getIDToken()
    }

    // ── Request builder ───────────────────────────────────────────────────────

    private func request(
        method: String,
        path: String,
        body: Data? = nil,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> URLRequest {
        var components = URLComponents(string: APIConfig.baseURL + path)
        components?.queryItems = queryItems?.isEmpty == false ? queryItems : nil

        guard let url = components?.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if Auth.auth().currentUser != nil {
            let token = try await idToken()
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        req.httpBody = body
        return req
    }

    // ── Execute ───────────────────────────────────────────────────────────────

    func execute<T: Decodable>(_ type: T.Type, method: String, path: String,
                               body: Data? = nil, queryItems: [URLQueryItem]? = nil) async throws -> T {
        let req = try await request(method: method, path: path, body: body, queryItems: queryItems)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.networkError(URLError(.badServerResponse)) }

        switch http.statusCode {
        case 200...299:
            do {
                return try decoder.decode(type, from: data)
            } catch {
                throw APIError.decodingFailed(error)
            }
        case 401: throw APIError.unauthorized
        case 404: throw APIError.notFound
        default:
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.serverError(http.statusCode, msg)
        }
    }

    func executeVoid(method: String, path: String, body: Data? = nil) async throws {
        let req = try await request(method: method, path: path, body: body)
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 { throw APIError.unauthorized }
        if http.statusCode >= 400 { throw APIError.serverError(http.statusCode, "") }
    }

    // ── Convenience ───────────────────────────────────────────────────────────

    func get<T: Decodable>(_ type: T.Type, path: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        try await execute(type, method: "GET", path: path, queryItems: queryItems)
    }

    func post<T: Decodable>(_ type: T.Type, path: String, encodable: some Encodable) async throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(encodable)
        return try await execute(type, method: "POST", path: path, body: body)
    }

    func put<T: Decodable>(_ type: T.Type, path: String, encodable: some Encodable) async throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(encodable)
        return try await execute(type, method: "PUT", path: path, body: body)
    }

    func patch<T: Decodable>(_ type: T.Type, path: String, encodable: some Encodable) async throws -> T {
        let encoder = JSONEncoder()
        let body = try encoder.encode(encodable)
        return try await execute(type, method: "PATCH", path: path, body: body)
    }

    func delete(path: String) async throws {
        try await executeVoid(method: "DELETE", path: path)
    }
}
