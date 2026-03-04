import Foundation

enum SearchEntityType: String, Codable {
    case store
    case menu
}

struct SearchResultItem: Identifiable, Codable, Hashable {
    var id: String
    var entityType: SearchEntityType
    var title: String
    var subtitle: String?
    var restaurantId: String?
    var restaurantName: String?
    var imageUrl: String?
    var price: Double?
    var rating: Double?
    var score: Double
}

struct UnifiedSearchResponse: Codable {
    var query: String
    var stores: [SearchResultItem]
    var menuItems: [SearchResultItem]
    var similarMenuItems: [SearchResultItem]
    var nextOffset: Int?
    var hasMore: Bool
}
