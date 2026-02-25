import Foundation

// MARK: - APIAdminUser

struct APIAdminUser: Decodable, Identifiable {
    var id: String
    var email: String?
    var displayName: String?
    var role: String
    var city: String?
    var managedRestaurantId: String?

    enum CodingKeys: String, CodingKey {
        case id, email, role, city
        case displayName         = "display_name"
        case managedRestaurantId = "managed_restaurant_id"
    }

    func toAppUser() -> AppUser {
        AppUser(
            id: id, email: email ?? "",
            role: AuthService.mapAPIRole(role),
            managedRestaurantId: managedRestaurantId,
            fullName: displayName
        )
    }
}

struct APIAdminUsersPage: Decodable {
    let users: [APIAdminUser]
    let total: Int
    let offset: Int
    let limit: Int
    let nextOffset: Int?
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case users, total, offset, limit, hasMore
        case nextOffset = "next_offset"
    }
}

struct AdminUsersPage {
    let users: [AppUser]
    let total: Int
    let offset: Int
    let limit: Int
    let nextOffset: Int?
    let hasMore: Bool
}

// MARK: - AdminStats

struct AdminStats: Decodable {
    var totalUsers: Int
    var storeOwnerCount: Int
    var totalRestaurants: Int
    var activeRestaurants: Int
    var totalOrders: Int
    var todayOrders: Int
}

// MARK: - AdminAPIService

struct AdminAPIService {
    private let client = APIClient.shared

    private enum CacheKeys {
        static let adminUsers = "admin.users.cache.v1"
        static let adminUsersUpdatedAt = "admin.users.cache.updatedAt.v1"
    }

    // ── Kullanıcı Yönetimi ────────────────────────────────────────────────────

    func fetchAllUsers() async throws -> [AppUser] {
        let api = try await client.get([APIAdminUser].self, path: "/admin/users")
        let users = api.map { $0.toAppUser() }
        saveUsersToCache(users)
        return users
    }

    func fetchUsersPage(
        offset: Int,
        limit: Int = 50,
        search: String? = nil,
        role: UserRole? = nil,
        city: String? = nil
    ) async throws -> AdminUsersPage {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let search, !search.trimmingCharacters(in: .whitespaces).isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        if let role {
            let backendRole: String
            switch role {
            case .superAdmin:
                backendRole = "admin"
            case .storeOwner:
                backendRole = "storeOwner"
            case .user:
                backendRole = "user"
            }
            queryItems.append(URLQueryItem(name: "role", value: backendRole))
        }
        if let city, !city.trimmingCharacters(in: .whitespaces).isEmpty {
            queryItems.append(URLQueryItem(name: "city", value: city))
        }

        let api = try await client.get(
            APIAdminUsersPage.self,
            path: "/admin/users/paged",
            queryItems: queryItems
        )
        let users = api.users.map { $0.toAppUser() }
        return AdminUsersPage(
            users: users,
            total: api.total,
            offset: api.offset,
            limit: api.limit,
            nextOffset: api.nextOffset,
            hasMore: api.hasMore
        )
    }

    func loadCachedUsers(maxAge: TimeInterval = 300) -> [AppUser] {
        guard let lastUpdated = UserDefaults.standard.object(forKey: CacheKeys.adminUsersUpdatedAt) as? Date else {
            return []
        }
        guard Date().timeIntervalSince(lastUpdated) <= maxAge else {
            return []
        }
        guard let data = UserDefaults.standard.data(forKey: CacheKeys.adminUsers) else {
            return []
        }
        return (try? JSONDecoder().decode([AppUser].self, from: data)) ?? []
    }

    func saveUsersToCache(_ users: [AppUser]) {
        guard let data = try? JSONEncoder().encode(users) else { return }
        UserDefaults.standard.set(data, forKey: CacheKeys.adminUsers)
        UserDefaults.standard.set(Date(), forKey: CacheKeys.adminUsersUpdatedAt)
    }

    func clearUsersCache() {
        UserDefaults.standard.removeObject(forKey: CacheKeys.adminUsers)
        UserDefaults.standard.removeObject(forKey: CacheKeys.adminUsersUpdatedAt)
    }

    func createUser(email: String, password: String,
                    displayName: String?, role: UserRole) async throws -> AppUser {
        struct Body: Encodable {
            var email: String; var password: String
            var displayName: String?
            var role: String
        }
        let backendRole = role == .superAdmin ? "admin" : role.rawValue
        let api = try await client.post(
            APIAdminUser.self,
            path: "/admin/users",
            encodable: Body(email: email, password: password, displayName: displayName, role: backendRole)
        )
        return api.toAppUser()
    }

    func updateUserRole(uid: String, role: UserRole) async throws {
        struct RoleBody: Encodable { var role: String }
        let backendRole = role == .superAdmin ? "admin" : role.rawValue
        _ = try await client.patch(
            APIAdminUser.self,
            path: "/admin/users/\(uid)/role",
            encodable: RoleBody(role: backendRole)
        )
    }

    func deleteUser(uid: String) async throws {
        try await client.delete(path: "/admin/users/\(uid)")
    }

    // ── Co-owner Desteği ──────────────────────────────────────────────────────

    /// Kullanıcıyı mevcut bir restorana ortak sahip olarak atar.
    /// - restaurantId: nil gönderilirse bağ koparılır.
    func assignManagedRestaurant(uid: String, restaurantId: String?) async throws -> AppUser {
        struct Body: Encodable { var restaurantId: String? }
        let api = try await client.patch(
            APIAdminUser.self,
            path: "/admin/users/\(uid)/managed-restaurant",
            encodable: Body(restaurantId: restaurantId)
        )
        return api.toAppUser()
    }

    // ── İstatistikler ─────────────────────────────────────────────────────────

    func fetchStats() async throws -> AdminStats {
        return try await client.get(AdminStats.self, path: "/admin/stats")
    }

    // ── Restoran Yönetimi ─────────────────────────────────────────────────────

    func fetchAllRestaurants() async throws -> [Restaurant] {
        let api = try await client.get([APIRestaurant].self, path: "/admin/restaurants")
        return api.map { $0.toRestaurant() }
    }

    func deleteRestaurant(id: String) async throws {
        try await client.delete(path: "/restaurants/\(id)")
    }

    func toggleRestaurantActive(id: String) async throws -> Restaurant {
        struct Empty: Encodable {}
        let api = try await client.patch(
            APIRestaurant.self,
            path: "/admin/restaurants/\(id)/toggle",
            encodable: Empty()
        )
        return api.toRestaurant()
    }
}
