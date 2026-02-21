import Foundation

// MARK: - OrderStatus

enum OrderStatus: String, Codable, CaseIterable {
    case pending    = "pending"     // Beklemede (yeni sipariş)
    case accepted   = "accepted"    // Kabul edildi
    case rejected   = "rejected"    // Reddedildi
    case preparing  = "preparing"   // Hazırlanıyor
    case onTheWay   = "onTheWay"    // Yolda
    case completed  = "completed"   // Teslim edildi
    case cancelled  = "cancelled"   // İptal edildi

    var displayName: String {
        switch self {
        case .pending:   return "Beklemede"
        case .accepted:  return "Kabul Edildi"
        case .rejected:  return "Reddedildi"
        case .preparing: return "Hazırlanıyor"
        case .onTheWay:  return "Yolda"
        case .completed: return "Teslim Edildi"
        case .cancelled: return "İptal Edildi"
        }
    }

    var icon: String {
        switch self {
        case .pending:   return "clock"
        case .accepted:  return "checkmark.circle"
        case .rejected:  return "xmark.circle"
        case .preparing: return "flame"
        case .onTheWay:  return "bicycle"
        case .completed: return "checkmark.seal.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    var color: String {   // SwiftUI Color name — mapped in views
        switch self {
        case .pending:   return "orange"
        case .accepted:  return "blue"
        case .rejected:  return "red"
        case .preparing: return "yellow"
        case .onTheWay:  return "teal"
        case .completed: return "green"
        case .cancelled: return "gray"
        }
    }
}

// MARK: - PaymentMethod

enum PaymentMethod: String, Codable, CaseIterable {
    case onlineCard    = "onlineCard"     // Pasif – sanal pos yok
    case cashOnDelivery = "cashOnDelivery"
    case cardOnDelivery = "cardOnDelivery"
    case pickup        = "pickup"         // Gel-al

    var displayName: String {
        switch self {
        case .onlineCard:     return "Online Kart (Yakında)"
        case .cashOnDelivery: return "Kapıda Nakit"
        case .cardOnDelivery: return "Kapıda Kart"
        case .pickup:         return "Gel & Al"
        }
    }
}

// MARK: - SelectedOption (sepete eklenmiş ürünün seçimi)

struct SelectedOptionGroup: Codable, Identifiable {
    var id: String = UUID().uuidString
    var groupName: String
    var selectedOptions: [String]    // Option names
    var extraTotal: Double = 0       // Toplam extra ücret
}

// MARK: - OrderItem

struct OrderItem: Identifiable, Codable {
    var id: String = UUID().uuidString
    var menuItemId: String
    var name: String
    var unitPrice: Double              // discounted base price at order time
    var quantity: Int
    var selectedOptionGroups: [SelectedOptionGroup] = []
    var optionExtrasPerUnit: Double = 0 // extra cost per unit from options
    var imageUrl: String? = nil

    var pricePerUnit: Double { unitPrice + optionExtrasPerUnit }
    var lineTotal: Double { pricePerUnit * Double(quantity) }

    var optionSummary: String {
        selectedOptionGroups
            .flatMap { $0.selectedOptions }
            .joined(separator: ", ")
    }
}

// MARK: - Order

struct Order: Identifiable, Codable {
    var id: String = UUID().uuidString
    var restaurantId: String
    var restaurantName: String
    var userId: String
    var userEmail: String
    var items: [OrderItem]
    var subtotal: Double
    var deliveryFee: Double = 0
    var total: Double
    var status: OrderStatus = .pending
    var paymentMethod: PaymentMethod
    var deliveryAddress: UserAddress?
    var pickupCode: String?
    var note: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isReviewed: Bool = false
    // ── Cancel request (user-initiated, owner must approve) ───────
    var cancelRequested: Bool = false
    var cancelReason: String = ""
    var cancelRequestedAt: Date? = nil
    // ── Coupon discounts ──────────────────────────────────────────
    var appliedCoupons: [AppliedCoupon] = []
    var discountAmount: Double = 0

    // Convenience
    var itemCount: Int { items.reduce(0) { $0 + $1.quantity } }
    var formattedDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "dd MMM yyyy, HH:mm"
        return f.string(from: createdAt)
    }
}

// MARK: - OrderReview

struct OrderReview: Identifiable, Codable {
    var id: String = UUID().uuidString
    var orderId: String
    var restaurantId: String
    var userId: String
    var speedRating: Double = 0       // 1-5
    var tasteRating: Double = 0       // 1-5
    var presentationRating: Double = 0 // 1-5
    var comment: String = ""
    var createdAt: Date = Date()

    var averageRating: Double {
        (speedRating + tasteRating + presentationRating) / 3.0
    }
}
