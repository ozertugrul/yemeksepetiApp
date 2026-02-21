import Foundation

// MARK: - APIAdminUser

/// Admin kullanıcı listesi için backend 'UserOut' response
struct APIAdminUser: Decodable, Identifiable {
    var id: String
    var email: String?
    var displayName: String?
    var role: String
    var city: String?
    var managedRestaurantId: String?

    /// Backend 'admin' rolünü iOS 'superAdmin' ile eşleştir
    func toAppUser() -> AppUser {
        let mappedRole: UserRole
        switch role {
        case "admin":      mappedRole = .superAdmin
        case "storeOwner": mappedRole = .storeOwner
        default:           mappedRole = .user
        }
        return AppUser(
            id: id,
            email: email ?? "",
            role: mappedRole,
            managedRestaurantId: managedRestaurantId,
            fullName: displayName
        )
    }
}

// MARK: - AdminAPIService

struct AdminAPIService {
    private let client = APIClient.shared

    // ── Kullanıcı Yönetimi ────────────────────────────────────────────────────

    func fetchAllUsers() async throws -> [AppUser] {
        let api = try await client.get([APIAdminUser].self, path: "/admin/users")
        return api.map { $0.toAppUser() }
    }

    func updateUserRole(uid: String, role: UserRole) async throws {
        struct RoleBody: Encodable { var role: String }
        // iOS superAdmin → backend "admin"
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

    // ── Restoran Yönetimi ─────────────────────────────────────────────────────

    func fetchAllRestaurants() async throws -> [Restaurant] {
        let api = try await client.get(
            [APIRestaurant].self,
            path: "/restaurants/admin/all"
        )
        return api.map { $0.toRestaurant() }
    }

    /// Restoranı sil (admin)
    func deleteRestaurant(id: String) async throws {
        try await client.delete(path: "/restaurants/\(id)")
    }
}
