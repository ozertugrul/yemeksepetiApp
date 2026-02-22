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

// MARK: - RestaurantAPIService

/// FastAPI üzerinden restoran işlemleri.
/// APIConfig.useSQLBackend = false ise DataService (Firestore) kullanılır.
struct RestaurantAPIService {
    private let client = APIClient.shared

    func fetchActive(city: String? = nil) async throws -> [Restaurant] {
        var items: [URLQueryItem] = []
        if let city { items.append(URLQueryItem(name: "city", value: city)) }
        let apiList = try await client.get([APIRestaurant].self, path: "/restaurants", queryItems: items)
        return apiList.map { $0.toRestaurant() }
    }

    func fetchDetail(id: String) async throws -> Restaurant {
        let r = try await client.get(APIRestaurant.self, path: "/restaurants/\(id)")
        return r.toRestaurant()
    }

    func fetchMyRestaurant() async throws -> Restaurant {
        let r = try await client.get(APIRestaurant.self, path: "/restaurants/my")
        return r.toRestaurant()
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
        return api.toRestaurant()
    }

    func upsertMenuItem(restaurantId: String, item: MenuItem) async throws {
        _ = try await client.post(APIMenuItem.self,
                                  path: "/restaurants/\(restaurantId)/menu",
                                  encodable: MenuItemBody(from: item, restaurantId: restaurantId))
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

    /// Serbest metin sorgusuna göre menü öğesi önerisi al
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

    /// Belirtilen restoran için tüm menü öğelerinin embedding'ini yenile (owner trigger)
    func refreshEmbeddings(restaurantId: String) async throws {
        try await client.executeVoid(
            method: "POST",
            path: "/recommendations/embed/batch?restaurant_id=\(restaurantId)"
        )
    }
}
