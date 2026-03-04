import Foundation

extension Notification.Name {
    nonisolated static let apiUnauthorized = Notification.Name("apiUnauthorized")
    nonisolated static let apiForbidden = Notification.Name("apiForbidden")
}

// MARK: - APIConfigEDbw2ed$JV#RhFT

enum APIConfig {
    private nonisolated static let defaultDockerHostBaseURL = "http://88.224.106.3:8000/api/v1"

    nonisolated static var baseURL: String {
        if let env = ProcessInfo.processInfo.environment["API_BASE_URL"], !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return normalizedBaseURL(env)
        }

        return defaultDockerHostBaseURL
    }

    private nonisolated static func normalizedBaseURL(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix("/api/v1") { return value }
        return value + "/api/v1"
    }

    static var useRecommendations: Bool {
        ProcessInfo.processInfo.environment["USE_RECOMMENDATIONS"] != "false"
    }
}

// MARK: - APIError

enum APIError: Error, LocalizedError {
    case invalidURL
    case unauthorized(message: String?)
    case forbidden
    case notFound
    case serverError(Int, String)
    case decodingFailed(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Geçersiz URL"
        case .unauthorized(let message):
            if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return message
            }
            return "Oturum süreniz dolmuş, lütfen tekrar giriş yapın."
        case .forbidden:           return "Bu işlem için yetkiniz yok."
        case .notFound:            return "İçerik bulunamadı."
        case .serverError(let c, let m): return "Sunucu hatası (\(c)): \(m)"
        case .decodingFailed(let e):     return "Veri çözümleme hatası: \(e)"
        case .networkError(let e):       return "Ağ hatası: \(e)"
        }
    }
}

// MARK: - APIClient

/// Merkezi HTTP istemcisi — varsa Keychain JWT access token'ını ekler.
actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    private struct ErrorDetailResponse: Decodable {
        let detail: String?
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 40
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
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

        if let token = KeychainHelper.loadToken() {
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
        case 401:
            let detail = decodeErrorDetail(from: data)
            let isAuthEndpoint = path.hasPrefix("/auth/")
            if !isAuthEndpoint {
                NotificationCenter.default.post(name: .apiUnauthorized, object: nil)
            }
            throw APIError.unauthorized(message: detail)
        case 403:
            NotificationCenter.default.post(name: .apiForbidden, object: nil)
            throw APIError.forbidden
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
        if http.statusCode == 401 {
            let isAuthEndpoint = path.hasPrefix("/auth/")
            if !isAuthEndpoint {
                NotificationCenter.default.post(name: .apiUnauthorized, object: nil)
            }
            throw APIError.unauthorized(message: nil)
        }
        if http.statusCode == 403 {
            NotificationCenter.default.post(name: .apiForbidden, object: nil)
            throw APIError.forbidden
        }
        if http.statusCode >= 400 {
            throw APIError.serverError(http.statusCode, "")
        }
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

    private nonisolated func decodeErrorDetail(from data: Data) -> String? {
        if let parsed = try? JSONDecoder().decode(ErrorDetailResponse.self, from: data),
           let detail = parsed.detail,
           !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return detail
        }
        let fallback = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fallback, !fallback.isEmpty {
            return fallback
        }
        return nil
    }
}
