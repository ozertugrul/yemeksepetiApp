import Foundation

// MARK: - API Response Types

struct APIUserProfile: Decodable {
    var id: String
    var email: String?
    var displayName: String?
    var role: String
    var city: String?
    var phone: String?
    var managedRestaurantId: String?

    enum CodingKeys: String, CodingKey {
        case id, email, role, city, phone
        case displayName          = "display_name"
        case managedRestaurantId  = "managed_restaurant_id"
    }
}

struct APIUserAddress: Decodable {
    var id: String
    var userId: String
    var title: String
    var city: String
    var district: String
    var neighborhood: String
    var street: String
    var buildingNo: String
    var flatNo: String
    var directions: String
    var isDefault: Bool
    var phone: String
    var latitude: Double?
    var longitude: Double?

    func toUserAddress() -> UserAddress {
        UserAddress(
            id: id, title: title, city: city,
            district: district, neighborhood: neighborhood,
            street: street, buildingNo: buildingNo, flatNo: flatNo,
            directions: directions, isDefault: isDefault,
            phone: phone, latitude: latitude, longitude: longitude
        )
    }
}

// MARK: - UserAPIService

struct UserAPIService {
    private let client = APIClient.shared

    // ── Profil ───────────────────────────────────────────────────────────────

    /// Mevcut kullanıcı profilini çek. PostgreSQL'de yoksa otomatik oluşturulur.
    func fetchMyProfile() async throws -> APIUserProfile {
        try await client.get(APIUserProfile.self, path: "/users/me")
    }

    /// Profili güncelle (displayName, city, phone).
    func updateMyProfile(displayName: String? = nil,
                         city: String? = nil,
                         phone: String? = nil) async throws -> APIUserProfile {
        var body: [String: String] = [:]
        if let n = displayName { body["display_name"] = n }
        if let c = city { body["city"] = c }
        if let p = phone { body["phone"] = p }
        return try await client.put(APIUserProfile.self, path: "/users/me", encodable: body)
    }

    // ── Adresler ──────────────────────────────────────────────────────────────

    func fetchAddresses() async throws -> [UserAddress] {
        let api = try await client.get([APIUserAddress].self, path: "/users/me/addresses")
        return api.map { $0.toUserAddress() }
    }

    func createAddress(_ address: UserAddress) async throws -> UserAddress {
        let body = AddressBody(from: address)
        let api = try await client.post(APIUserAddress.self, path: "/users/me/addresses", encodable: body)
        return api.toUserAddress()
    }

    func updateAddress(_ address: UserAddress) async throws -> UserAddress {
        let body = AddressBody(from: address)
        let api = try await client.put(APIUserAddress.self,
                                       path: "/users/me/addresses/\(address.id)",
                                       encodable: body)
        return api.toUserAddress()
    }

    func deleteAddress(id: String) async throws {
        try await client.delete(path: "/users/me/addresses/\(id)")
    }
}

// MARK: - Encodable Bodies

private struct AddressBody: Encodable {
    var title: String
    var city: String
    var district: String
    var neighborhood: String
    var street: String
    var buildingNo: String
    var flatNo: String
    var directions: String
    var isDefault: Bool
    var phone: String
    var latitude: Double?
    var longitude: Double?

    init(from a: UserAddress) {
        title = a.title; city = a.city; district = a.district
        neighborhood = a.neighborhood; street = a.street
        buildingNo = a.buildingNo; flatNo = a.flatNo
        directions = a.directions; isDefault = a.isDefault
        phone = a.phone; latitude = a.latitude; longitude = a.longitude
    }
}
