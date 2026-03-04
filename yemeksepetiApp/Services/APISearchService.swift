import Foundation

protocol SearchServiceProtocol {
    func search(
        query: String,
        city: String?,
        offset: Int,
        limit: Int
    ) async throws -> UnifiedSearchResponse
}

struct APISearchService: SearchServiceProtocol {
    private let client = APIClient.shared
    private static let cache = SearchResponseCache()

    func search(
        query: String,
        city: String? = nil,
        offset: Int = 0,
        limit: Int = 20
    ) async throws -> UnifiedSearchResponse {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedCity = city?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let key = SearchCacheKey(
            query: normalizedQuery,
            city: normalizedCity,
            offset: offset,
            limit: limit
        )

        if let cached = await Self.cache.cachedValue(for: key) {
            return cached
        }

        if let inFlightTask = await Self.cache.inFlightTask(for: key) {
            return try await inFlightTask.value
        }

        let task = Task<UnifiedSearchResponse, Error> {
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "offset", value: "\(offset)"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
            if let city, !city.isEmpty {
                queryItems.append(URLQueryItem(name: "city", value: city))
            }

            let response = try await client.get(
                UnifiedSearchResponse.self,
                path: "/search/unified",
                queryItems: queryItems
            )
            await Self.cache.save(response, for: key)
            return response
        }

        await Self.cache.setInFlightTask(task, for: key)
        do {
            let value = try await task.value
            await Self.cache.clearInFlightTask(for: key)
            return value
        } catch {
            await Self.cache.clearInFlightTask(for: key)
            throw error
        }
    }
}

private struct SearchCacheKey: Hashable {
    let query: String
    let city: String?
    let offset: Int
    let limit: Int
}

private actor SearchResponseCache {
    private let ttl: TimeInterval = 25
    private var values: [SearchCacheKey: (value: UnifiedSearchResponse, savedAt: Date)] = [:]
    private var inFlight: [SearchCacheKey: Task<UnifiedSearchResponse, Error>] = [:]

    func cachedValue(for key: SearchCacheKey) -> UnifiedSearchResponse? {
        guard let entry = values[key] else { return nil }
        guard Date().timeIntervalSince(entry.savedAt) <= ttl else {
            values[key] = nil
            return nil
        }
        return entry.value
    }

    func save(_ value: UnifiedSearchResponse, for key: SearchCacheKey) {
        values[key] = (value: value, savedAt: Date())
    }

    func inFlightTask(for key: SearchCacheKey) -> Task<UnifiedSearchResponse, Error>? {
        inFlight[key]
    }

    func setInFlightTask(_ task: Task<UnifiedSearchResponse, Error>, for key: SearchCacheKey) {
        inFlight[key] = task
    }

    func clearInFlightTask(for key: SearchCacheKey) {
        inFlight[key] = nil
    }
}
