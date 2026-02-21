import Foundation

// MARK: - MenuItemOption

struct MenuItemOption: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var extraPrice: Double = 0        // 0 = included in base price
    var isDefault: Bool = false
}

// MARK: - MenuItemOptionGroup

enum OptionGroupType: String, Codable, CaseIterable {
    case singleSelect  = "singleSelect"   // Tek seçim (radio)
    case multiSelect   = "multiSelect"    // Çok seçim (checkbox)
}

struct MenuItemOptionGroup: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String                         // "Acılık Seviyesi", "Ekstralar"
    var type: OptionGroupType = .singleSelect
    var isRequired: Bool = false
    var minSelections: Int = 0               // 0 = optional
    var maxSelections: Int = 1               // for multiSelect
    var options: [MenuItemOption] = []
}

// MARK: - MenuItem

struct MenuItem: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var description: String
    var price: Double
    var imageUrl: String?
    var category: String = "Diğer"
    var discountPercent: Double = 0
    var isAvailable: Bool = true
    var optionGroups: [MenuItemOptionGroup] = []
    var suggestedItemIds: [String] = []     // "Yanında iyi gider" önerileri

    /// Calculated final price after discount
    var discountedPrice: Double {
        discountPercent > 0 ? price * (1 - discountPercent / 100) : price
    }
}

// MARK: - Restaurant

struct Restaurant: Identifiable, Codable {
    let id: String
    var name: String
    var ownerId: String?
    var description: String
    var cuisineType: String
    var imageUrl: String?
    var rating: Double
    var deliveryTime: String       // e.g. "30-45 dk"
    var minOrderAmount: Double
    var menu: [MenuItem]
    var isActive: Bool
    var city: String? = nil
    var allowsPickup: Bool = false             // Gel-al seçeneği
    var allowsCashOnDelivery: Bool = false     // Kapıda ödeme
    var successfulOrderCount: Int = 0          // Başarılı sipariş sayısı
    var averageRating: Double = 0              // Müşteri değerlendirme ortalaması
    var ratingCount: Int = 0                   // Değerlendirme sayısı
}
