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

    // ── Kullanıcı Yönetimi ────────────────────────────────────────────────────

    func fetchAllUsers() async throws -> [AppUser] {
        let api = try await client.get([APIAdminUser].self, path: "/admin/users")
        return api.map { $0.toAppUser() }
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
