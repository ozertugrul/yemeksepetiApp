import Foundation

// MARK: - RecommendationModels

struct RecommendationQuery: Encodable {
    var query: String
    var restaurantId: String?
    var topK: Int = 10
}

struct MenuItemRecommendation: Decodable {
    var score: Double
    var item: APIMenuItem
}

struct RecommendationResponse: Decodable {
    var query: String
    var results: [MenuItemRecommendation]
}

// MARK: - CF (Collaborative Filtering) Recommendation Models

struct CFMenuItemResponse: Decodable {
    var id: String
    var restaurantId: String
    var name: String
    var description: String
    var price: Double
    var imageUrl: String?
    var category: String
    var discountPercent: Double
    var isAvailable: Bool
    var optionGroups: [MenuItemOptionGroup]?
    var suggestedIds: [String]?
    var restaurantName: String?

    func toMenuItem() -> MenuItem {
        MenuItem(
            id: id, name: name, description: description,
            price: price, imageUrl: imageUrl, category: category,
            discountPercent: discountPercent, isAvailable: isAvailable,
            optionGroups: optionGroups ?? [], suggestedItemIds: suggestedIds ?? []
        )
    }
}

struct CFRecommendationItem: Decodable, Identifiable {
    var score: Double
    var source: String        // "cf" | "popular"
    var supporters: Int
    var item: CFMenuItemResponse

    var id: String { item.id }
}

struct CFRecommendationResponse: Decodable {
    var timeSegment: String        // "breakfast" | "lunch" | …
    var label: String              // "Öğle Yemeği" (TR)
    var items: [CFRecommendationItem]
}

// ── API dönüş tipleri (FastAPI şeması ile aynı) ───────────────────────────────

struct APIRestaurant: Decodable {
    var id: String
    var name: String
    var ownerId: String?
    var description: String
    var cuisineType: String
    var imageUrl: String?
    var rating: Double
    var deliveryTime: String
    var minOrderAmount: Double
    var isActive: Bool
    var city: String?
    var allowsPickup: Bool
    var allowsCashOnDelivery: Bool
    var successfulOrderCount: Int
    var averageRating: Double
    var ratingCount: Int
    var menu: [APIMenuItem]

    func toRestaurant() -> Restaurant {
        Restaurant(
            id: id, name: name, ownerId: ownerId,
            description: description, cuisineType: cuisineType,
            imageUrl: imageUrl, rating: rating,
            deliveryTime: deliveryTime, minOrderAmount: minOrderAmount,
            menu: menu.map { $0.toMenuItem() }, isActive: isActive,
            city: city, allowsPickup: allowsPickup,
            allowsCashOnDelivery: allowsCashOnDelivery,
            successfulOrderCount: successfulOrderCount,
            averageRating: averageRating, ratingCount: ratingCount
        )
    }
}

struct APIMenuItem: Decodable {
    var id: String
    var restaurantId: String
    var name: String
    var description: String
    var price: Double
    var imageUrl: String?
    var category: String
    var discountPercent: Double
    var isAvailable: Bool
    var optionGroups: [MenuItemOptionGroup]
    var suggestedIds: [String]

    func toMenuItem() -> MenuItem {
        MenuItem(
            id: id, name: name, description: description,
            price: price, imageUrl: imageUrl, category: category,
            discountPercent: discountPercent, isAvailable: isAvailable,
            optionGroups: optionGroups, suggestedItemIds: suggestedIds
        )
    }
}

// MARK: - Paginated response

struct APIRestaurantsPage: Decodable {
    var restaurants: [APIRestaurant]
    var total: Int
    var offset: Int
    var limit: Int
    var nextOffset: Int?
    var hasMore: Bool
}

// MARK: - RestaurantAPIService

/// FastAPI üzerinden restoran işlemleri.
/// Tüm çağrılar API katmanı üzerinden çalışır.
struct RestaurantAPIService {
    private let client = APIClient.shared
    private static let detailCache = RestaurantDetailCache()

    func fetchActive(city: String? = nil) async throws -> [Restaurant] {
        var items: [URLQueryItem] = []
        if let city { items.append(URLQueryItem(name: "city", value: city)) }
        let apiList = try await client.get([APIRestaurant].self, path: "/restaurants", queryItems: items)
        return apiList.map { $0.toRestaurant() }
    }

    func fetchDetail(id: String) async throws -> Restaurant {
        if let cached = await Self.detailCache.cachedValue(for: id) {
            return cached
        }

        if let inFlightTask = await Self.detailCache.inFlightTask(for: id) {
            return try await inFlightTask.value
        }

        let task = Task<Restaurant, Error> {
            let response = try await client.get(APIRestaurant.self, path: "/restaurants/\(id)")
            let value = response.toRestaurant()
            await Self.detailCache.save(value, for: id)
            return value
        }

        await Self.detailCache.setInFlightTask(task, for: id)
        do {
            let value = try await task.value
            await Self.detailCache.clearInFlightTask(for: id)
            return value
        } catch {
            await Self.detailCache.clearInFlightTask(for: id)
            throw error
        }
    }

    func fetchMyRestaurant() async throws -> Restaurant {
        let r = try await client.get(APIRestaurant.self, path: "/restaurants/my")
        return r.toRestaurant()
    }

    // MARK: - Paginated (HomeView)

    func fetchActivePage(
        offset: Int,
        limit: Int = 20,
        search: String? = nil,
        city: String? = nil,
        cuisine: String? = nil
    ) async throws -> (restaurants: [Restaurant], total: Int, hasMore: Bool, nextOffset: Int?) {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if let s = search, !s.isEmpty   { items.append(URLQueryItem(name: "search",  value: s)) }
        if let c = city, !c.isEmpty     { items.append(URLQueryItem(name: "city",    value: c)) }
        if let cu = cuisine, !cu.isEmpty { items.append(URLQueryItem(name: "cuisine", value: cu)) }

        let page = try await client.get(APIRestaurantsPage.self, path: "/restaurants/paged", queryItems: items)
        return (
            restaurants: page.restaurants.map { $0.toRestaurant() },
            total: page.total,
            hasMore: page.hasMore,
            nextOffset: page.nextOffset
        )
    }

    func fetchDistinctCuisines(city: String? = nil) async throws -> [String] {
        var items: [URLQueryItem] = []
        if let c = city, !c.isEmpty { items.append(URLQueryItem(name: "city", value: c)) }
        return try await client.get([String].self, path: "/restaurants/distinct-cuisines", queryItems: items)
    }

    // MARK: - Admin / Owner CRUD

    func createRestaurant(_ restaurant: Restaurant) async throws -> Restaurant {
        let api = try await client.post(APIRestaurant.self, path: "/restaurants",
                                        encodable: RestaurantBody(from: restaurant))
        return api.toRestaurant()
    }

    func updateRestaurant(_ restaurant: Restaurant) async throws -> Restaurant {
        let api = try await client.put(APIRestaurant.self,
                                       path: "/restaurants/\(restaurant.id)",
                                       encodable: RestaurantBody(from: restaurant))
        let updated = api.toRestaurant()
        await Self.detailCache.save(updated, for: updated.id)
        return updated
    }

    func upsertMenuItem(restaurantId: String, item: MenuItem) async throws {
        _ = try await client.post(APIMenuItem.self,
                                  path: "/restaurants/\(restaurantId)/menu",
                                  encodable: MenuItemBody(from: item, restaurantId: restaurantId))
    }
}

private actor RestaurantDetailCache {
    private let ttl: TimeInterval = 120
    private var values: [String: (value: Restaurant, savedAt: Date)] = [:]
    private var inFlight: [String: Task<Restaurant, Error>] = [:]

    func cachedValue(for id: String) -> Restaurant? {
        guard let entry = values[id] else { return nil }
        guard Date().timeIntervalSince(entry.savedAt) <= ttl else {
            values[id] = nil
            return nil
        }
        return entry.value
    }

    func save(_ value: Restaurant, for id: String) {
        values[id] = (value: value, savedAt: Date())
    }

    func inFlightTask(for id: String) -> Task<Restaurant, Error>? {
        inFlight[id]
    }

    func setInFlightTask(_ task: Task<Restaurant, Error>, for id: String) {
        inFlight[id] = task
    }

    func clearInFlightTask(for id: String) {
        inFlight[id] = nil
    }
}

// MARK: - Request Body types

private struct RestaurantBody: Encodable {
    var id: String
    var name: String
    var ownerId: String?
    var description: String
    var cuisineType: String
    var imageUrl: String?
    var rating: Double
    var deliveryTime: String
    var minOrderAmount: Double
    var isActive: Bool
    var city: String?
    var allowsPickup: Bool
    var allowsCashOnDelivery: Bool

    init(from r: Restaurant) {
        id = r.id; name = r.name; ownerId = r.ownerId
        description = r.description; cuisineType = r.cuisineType
        imageUrl = r.imageUrl; rating = r.rating
        deliveryTime = r.deliveryTime; minOrderAmount = r.minOrderAmount
        isActive = r.isActive; city = r.city
        allowsPickup = r.allowsPickup; allowsCashOnDelivery = r.allowsCashOnDelivery
    }
}

private struct MenuItemBody: Encodable {
    var id: String
    var restaurantId: String
    var name: String
    var description: String
    var price: Double
    var imageUrl: String?
    var category: String
    var discountPercent: Double
    var isAvailable: Bool
    var optionGroups: [MenuItemOptionGroup]
    var suggestedIds: [String]

    init(from item: MenuItem, restaurantId: String) {
        id = item.id; self.restaurantId = restaurantId
        name = item.name; description = item.description
        price = item.price; imageUrl = item.imageUrl
        category = item.category; discountPercent = item.discountPercent
        isAvailable = item.isAvailable; optionGroups = item.optionGroups
        suggestedIds = item.suggestedItemIds
    }
}

// MARK: - RecommendationService

struct RecommendationService {
    private let client = APIClient.shared

    /// Serbest metin sorgusuna göre menü öğesi önerisi al (embedding-based)
    func recommend(
        query: String,
        restaurantId: String? = nil,
        topK: Int = 10
    ) async throws -> [MenuItemRecommendation] {
        guard APIConfig.useRecommendations else { return [] }
        let body = RecommendationQuery(query: query, restaurantId: restaurantId, topK: topK)
        let response = try await client.post(
            RecommendationResponse.self,
            path: "/recommendations/menu",
            encodable: body
        )
        return response.results
    }

    /// Kişiselleştirilmiş saat-bazlı collaborative filtering önerileri
    func personalRecommendations(
        city: String? = nil,
        topN: Int = 15,
        timeSegment: String? = nil
    ) async throws -> CFRecommendationResponse {
        guard APIConfig.useRecommendations else {
            return CFRecommendationResponse(timeSegment: "", label: "", items: [])
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "top_n", value: "\(topN)")
        ]
        if let city, !city.isEmpty {
            queryItems.append(URLQueryItem(name: "city", value: city))
        }
        if let ts = timeSegment, !ts.isEmpty {
            queryItems.append(URLQueryItem(name: "time_segment", value: ts))
        }
        return try await client.get(
            CFRecommendationResponse.self,
            path: "/recommendations/personal",
            queryItems: queryItems
        )
    }

    /// Şu anki zaman dilimindeki popüler ürünler (auth opsiyonel)
    func popularNow(
        city: String? = nil,
        topN: Int = 10
    ) async throws -> CFRecommendationResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "top_n", value: "\(topN)")
        ]
        if let city, !city.isEmpty {
            queryItems.append(URLQueryItem(name: "city", value: city))
        }
        return try await client.get(
            CFRecommendationResponse.self,
            path: "/recommendations/popular-now",
            queryItems: queryItems
        )
    }

    /// Belirtilen restoran için tüm menü öğelerinin embedding'ini yenile (owner trigger)
    func refreshEmbeddings(restaurantId: String) async throws {
        try await client.executeVoid(
            method: "POST",
            path: "/recommendations/embed/batch?restaurant_id=\(restaurantId)"
        )
    }
}
