import Foundation
import Combine

// CouponService — Firestore kaldırıldı; kupon API'si henüz backend'e eklenmedi.
// Tüm owner metodları no-op döner; kullanıcı metodları boş liste döner.

final class CouponService: ObservableObject {

    // MARK: - Validation Error

    enum CouponValidationError: LocalizedError {
        case notFound, inactive, expired, minCartNotMet(Double)
        case totalLimitReached, userLimitReached, wrongRestaurant, alreadyApplied

        var errorDescription: String? {
            switch self {
            case .notFound:              return "Kupon bulunamadı."
            case .inactive:             return "Bu kupon aktif değil."
            case .expired:              return "Bu kuponun süresi dolmuş."
            case .minCartNotMet(let m): return String(format: "Minimum sepet tutarı ₺%.2f olmalı.", m)
            case .totalLimitReached:    return "Bu kuponun genel kullanım limiti dolmuş."
            case .userLimitReached:     return "Bu kuponu daha fazla kullanamazsınız."
            case .wrongRestaurant:      return "Bu kupon yalnızca belirtilen mağazada geçerlidir."
            case .alreadyApplied:       return "Bu kupon zaten sepete eklendi."
            }
        }
    }

    // MARK: - Owner CRUD (stub)

    func createCoupon(_ coupon: Coupon, completion: @escaping (Error?) -> Void) {
        DispatchQueue.main.async { completion(nil) }
    }

    func updateCoupon(_ coupon: Coupon, completion: @escaping (Error?) -> Void) {
        DispatchQueue.main.async { completion(nil) }
    }

    func deleteCoupon(_ couponId: String, completion: @escaping (Error?) -> Void) {
        DispatchQueue.main.async { completion(nil) }
    }

    func listenStoreCoupons(restaurantId: String, onUpdate: @escaping ([Coupon]) -> Void) -> ListenerRegistration {
        // Fires once with empty list; polling interval unused since we have no backend endpoint
        onUpdate([])
        return ListenerRegistration(interval: 3600, fireImmediately: false) { }
    }

    // MARK: - Public Coupons (stub)

    func fetchPublicCoupons(city: String?, completion: @escaping ([Coupon]) -> Void) {
        DispatchQueue.main.async { completion([]) }
    }

    func fetchApplicableCoupons(restaurantId: String, cartTotal: Double, city: String?,
                               completion: @escaping ([Coupon]) -> Void) {
        DispatchQueue.main.async { completion([]) }
    }

    // MARK: - Validation (stub)

    func validateCoupon(code: String, restaurantId: String?, cartTotal: Double, userId: String,
                        alreadyAppliedIds: [String] = [],
                        completion: @escaping (Result<Coupon, Error>) -> Void) {
        DispatchQueue.main.async { completion(.failure(CouponValidationError.notFound)) }
    }

    // MARK: - Usage Tracking (stub)

    func recordUsages(couponIds: [String], userId: String) { }
}
