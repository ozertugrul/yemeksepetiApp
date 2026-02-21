import Foundation
import Combine
import FirebaseFirestore

final class CouponService: ObservableObject {
    private let db = Firestore.firestore()
    private let couponsCol  = "coupons"
    private let usagesCol   = "couponUsages"

    // MARK: - Owner CRUD

    func createCoupon(_ coupon: Coupon, completion: @escaping (Error?) -> Void) {
        do {
            try db.collection(couponsCol).document(coupon.id).setData(from: coupon) { error in
                DispatchQueue.main.async { completion(error) }
            }
        } catch {
            DispatchQueue.main.async { completion(error) }
        }
    }

    func updateCoupon(_ coupon: Coupon, completion: @escaping (Error?) -> Void) {
        do {
            try db.collection(couponsCol).document(coupon.id).setData(from: coupon, merge: true) { error in
                DispatchQueue.main.async { completion(error) }
            }
        } catch {
            DispatchQueue.main.async { completion(error) }
        }
    }

    func deleteCoupon(_ couponId: String, completion: @escaping (Error?) -> Void) {
        db.collection(couponsCol).document(couponId).delete { error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    func listenStoreCoupons(
        restaurantId: String,
        onUpdate: @escaping ([Coupon]) -> Void
    ) -> ListenerRegistration {
        db.collection(couponsCol)
            .whereField("restaurantId", isEqualTo: restaurantId)
            .addSnapshotListener { snapshot, _ in
                let coupons = (snapshot?.documents.compactMap { try? $0.data(as: Coupon.self) } ?? [])
                    .sorted { $0.createdAt > $1.createdAt }
                DispatchQueue.main.async { onUpdate(coupons) }
            }
    }

    // MARK: - User: Public Coupons

    /// Herkese açık kuponları getirir. Genel kuponlar (restaurantId=nil) ve mağazaya özgü
    /// public kuponlar. Şehir filtresi uygulanır.
    func fetchPublicCoupons(city: String?, completion: @escaping ([Coupon]) -> Void) {
        db.collection(couponsCol)
            .whereField("isPublic", isEqualTo: true)
            .whereField("isActive", isEqualTo: true)
            .getDocuments { snapshot, _ in
                var all = (snapshot?.documents.compactMap { try? $0.data(as: Coupon.self) } ?? [])
                    .filter { !$0.isExpired }

                if let city = city, !city.isEmpty {
                    all = all.filter { c in
                        // Genel kuponlarda şehir yoksa tüm şehirlerde geçerli
                        guard let cCity = c.city, !cCity.isEmpty else { return true }
                        return cCity == city
                    }
                }
                DispatchQueue.main.async {
                    completion(all.sorted { $0.createdAt > $1.createdAt })
                }
            }
    }

    /// Ödeme ekranında mevcut restoran + sepet tutarına göre kullanılabilir
    /// public kuponları filtreler.
    func fetchApplicableCoupons(
        restaurantId: String,
        cartTotal: Double,
        city: String?,
        completion: @escaping ([Coupon]) -> Void
    ) {
        fetchPublicCoupons(city: city) { coupons in
            let filtered = coupons.filter { c in
                // Kapsam: genel kupon (nil) veya bu mağazaya özgü
                if let rid = c.restaurantId, rid != restaurantId { return false }
                // Min sepet tutarı
                if let min = c.minCartTotal, cartTotal < min { return false }
                // Toplam limit
                if let max = c.maxTotalUsage, c.usageCount >= max { return false }
                return true
            }
            completion(filtered)
        }
    }

    // MARK: - Validation

    enum CouponValidationError: LocalizedError {
        case notFound
        case inactive
        case expired
        case minCartNotMet(Double)
        case totalLimitReached
        case userLimitReached
        case wrongRestaurant
        case alreadyApplied

        var errorDescription: String? {
            switch self {
            case .notFound:              return "Kupon bulunamadı."
            case .inactive:             return "Bu kupon aktif değil."
            case .expired:              return "Bu kuponun süresi dolmuş."
            case .minCartNotMet(let m): return "Minimum sepet tutarı ₺\(String(format: "%.2f", m)) olmalı."
            case .totalLimitReached:    return "Bu kuponun genel kullanım limiti dolmuş."
            case .userLimitReached:     return "Bu kuponu daha fazla kullanamazsınız."
            case .wrongRestaurant:      return "Bu kupon yalnızca belirtilen mağazada geçerlidir."
            case .alreadyApplied:       return "Bu kupon zaten sepete eklendi."
            }
        }
    }

    /// Kodu doğrular ve koşulları kontrol eder. Başarılı olursa Coupon döndürür.
    func validateCoupon(
        code: String,
        restaurantId: String?,
        cartTotal: Double,
        userId: String,
        alreadyAppliedIds: [String] = [],
        completion: @escaping (Result<Coupon, Error>) -> Void
    ) {
        let upper = code.uppercased().trimmingCharacters(in: .whitespaces)
        db.collection(couponsCol)
            .whereField("code", isEqualTo: upper)
            .limit(to: 1)
            .getDocuments { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }
                guard let coupon = snapshot?.documents.compactMap({ try? $0.data(as: Coupon.self) }).first else {
                    DispatchQueue.main.async { completion(.failure(CouponValidationError.notFound)) }
                    return
                }
                // Zaten eklendi mi?
                if alreadyAppliedIds.contains(coupon.id) {
                    DispatchQueue.main.async { completion(.failure(CouponValidationError.alreadyApplied)) }
                    return
                }
                // Temel kontroller
                guard coupon.isActive else {
                    DispatchQueue.main.async { completion(.failure(CouponValidationError.inactive)) }
                    return
                }
                guard !coupon.isExpired else {
                    DispatchQueue.main.async { completion(.failure(CouponValidationError.expired)) }
                    return
                }
                if let min = coupon.minCartTotal, cartTotal < min {
                    DispatchQueue.main.async { completion(.failure(CouponValidationError.minCartNotMet(min))) }
                    return
                }
                if let max = coupon.maxTotalUsage, coupon.usageCount >= max {
                    DispatchQueue.main.async { completion(.failure(CouponValidationError.totalLimitReached)) }
                    return
                }
                // Restoran kapsamı
                if let cRid = coupon.restaurantId, let cartRid = restaurantId, cRid != cartRid {
                    DispatchQueue.main.async { completion(.failure(CouponValidationError.wrongRestaurant)) }
                    return
                }
                // Kullanıcı başına limit
                if let perUser = coupon.maxUsagePerUser {
                    self.getUserUsageCount(couponId: coupon.id, userId: userId) { count in
                        if count >= perUser {
                            DispatchQueue.main.async { completion(.failure(CouponValidationError.userLimitReached)) }
                        } else {
                            DispatchQueue.main.async { completion(.success(coupon)) }
                        }
                    }
                } else {
                    DispatchQueue.main.async { completion(.success(coupon)) }
                }
            }
    }

    // MARK: - Usage Tracking

    private func getUserUsageCount(couponId: String, userId: String, completion: @escaping (Int) -> Void) {
        db.collection(usagesCol)
            .document(couponId)
            .collection("users")
            .document(userId)
            .getDocument { snap, _ in
                let count = (snap?.data()?["count"] as? Int) ?? 0
                DispatchQueue.main.async { completion(count) }
            }
    }

    /// Sipariş tamamlandığında çağrılır. Kupon kullanım sayaçlarını artırır.
    func recordUsages(couponIds: [String], userId: String) {
        for couponId in couponIds {
            let couponRef = db.collection(couponsCol).document(couponId)
            let usageRef  = db.collection(usagesCol)
                .document(couponId).collection("users").document(userId)
            let batch = db.batch()
            batch.updateData(["usageCount": FieldValue.increment(Int64(1))], forDocument: couponRef)
            batch.setData(["count": FieldValue.increment(Int64(1))], forDocument: usageRef, merge: true)
            batch.commit { _ in }
        }
    }
}
