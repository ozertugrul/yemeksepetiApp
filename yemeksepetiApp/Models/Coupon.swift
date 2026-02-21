import Foundation

// MARK: - DiscountType

enum DiscountType: String, Codable, CaseIterable {
    case percentage = "percentage"   // Yüzde indirim
    case fixed      = "fixed"        // Sabit tutar indirimi

    var displayName: String {
        switch self {
        case .percentage: return "Yüzde (%)"
        case .fixed:      return "Sabit (₺)"
        }
    }
}

// MARK: - Coupon

struct Coupon: Identifiable, Codable {
    var id: String = UUID().uuidString
    var code: String                           // Kupon kodu (örn. "YEMEK20")
    var title: String                          // Kısa başlık
    var description: String = ""               // Açıklama

    // Kapsam: nil = genel kupon (tüm mağazalarda geçerli)
    var restaurantId: String?
    var restaurantName: String?

    // İndirim
    var discountType: DiscountType
    var discountValue: Double                  // % veya ₺ miktarı
    var maxDiscountAmount: Double?             // Yüzde indirimlerde üst limit

    // Koşullar
    var minCartTotal: Double?                  // Minimum sepet tutarı
    var maxTotalUsage: Int?                    // Toplam kullanım limiti (nil = sınırsız)
    var maxUsagePerUser: Int?                  // Kullanıcı başına limit

    // Görünürlük
    var isPublic: Bool = false                 // Kullanıcıların "Kuponlarım"da görünsün
    var city: String?                          // Genel kuponların şehir filtresi (nil = tüm şehirler)

    // Yaşam döngüsü
    var isActive: Bool = true
    var expiresAt: Date? = nil
    var usageCount: Int = 0
    var createdAt: Date = Date()
    var createdBy: String                      // Mağaza sahibinin UID

    // MARK: Hesaplamalar

    var isExpired: Bool {
        guard let exp = expiresAt else { return false }
        return exp < Date()
    }

    var isUsable: Bool { isActive && !isExpired }

    /// Verilen sepet tutarı için uygulanacak indirim miktarını hesaplar.
    func calculatedDiscount(for cartTotal: Double) -> Double {
        switch discountType {
        case .percentage:
            let raw = cartTotal * (discountValue / 100.0)
            if let cap = maxDiscountAmount { return min(raw, cap) }
            return raw
        case .fixed:
            return min(discountValue, cartTotal)
        }
    }

    var discountLabel: String {
        switch discountType {
        case .percentage:
            var s = "%\(Int(discountValue)) İndirim"
            if let cap = maxDiscountAmount { s += " (max ₺\(String(format: "%.0f", cap)))" }
            return s
        case .fixed:
            return "₺\(String(format: "%.2f", discountValue)) İndirim"
        }
    }
}

// MARK: - AppliedCoupon (Sipariş içine gömülür)

struct AppliedCoupon: Codable, Identifiable {
    var id: String { couponId }
    var couponId: String
    var code: String
    var discountAmount: Double
}
