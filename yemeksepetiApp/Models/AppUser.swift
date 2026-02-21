import Foundation

enum UserRole: String, Codable {
    case user
    case storeOwner
    case superAdmin
}

struct AppUser: Identifiable, Codable {
    let id: String
    let email: String
    let role: UserRole
    var managedRestaurantId: String? // For store owners
    var fullName: String? = nil
    var phone: String? = nil
    var city: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, email, role, managedRestaurantId, fullName, phone, city
    }
}
