import Foundation
import Combine

@MainActor
final class CouponService: ObservableObject {

    private struct CouponDTO: Codable {
        let id: String
        let restaurantId: String?
        let restaurantName: String?
        let code: String
        let description: String
        let discountAmount: Double
        let discountPercent: Double
        let minimumOrderAmount: Double
        let expiryDate: Date?
        let isActive: Bool
        let isPublic: Bool
        let city: String?
        let createdAt: Date?
    }

    private struct CouponUpsertRequest: Encodable {
        let id: String?
        let restaurantId: String?
        let code: String
        let description: String
        let discountAmount: Double
        let discountPercent: Double
        let minimumOrderAmount: Double
        let expiryDate: Date?
        let isActive: Bool
        let isPublic: Bool
        let city: String?
    }

    private struct CouponDeleteResponse: Decodable {
        let ok: Bool
    }

    private let ownerCouponsPollInterval: TimeInterval = 4

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

    // MARK: - Owner CRUD

    func createCoupon(_ coupon: Coupon, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                let payload = toUpsertRequest(coupon)
                _ = try await APIClient.shared.post(CouponDTO.self, path: "/coupons", encodable: payload)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func updateCoupon(_ coupon: Coupon, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                let payload = toUpsertRequest(coupon)
                _ = try await APIClient.shared.put(CouponDTO.self, path: "/coupons/\(coupon.id)", encodable: payload)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func deleteCoupon(_ couponId: String, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                _ = try await APIClient.shared.execute(CouponDeleteResponse.self, method: "DELETE", path: "/coupons/\(couponId)")
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func listenStoreCoupons(restaurantId: String, onUpdate: @escaping ([Coupon]) -> Void) -> ListenerRegistration {
        ListenerRegistration(interval: ownerCouponsPollInterval) {
            Task {
                let list = (try? await self.fetchStoreCoupons(restaurantId: restaurantId)) ?? []
                onUpdate(list)
            }
        }
    }

    // MARK: - Public Coupons

    func fetchPublicCoupons(city: String?, completion: @escaping ([Coupon]) -> Void) {
        Task {
            do {
                var query: [URLQueryItem] = []
                if let city, !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    query.append(URLQueryItem(name: "city", value: city.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
                let list = try await APIClient.shared.get([CouponDTO].self, path: "/coupons/public", queryItems: query.isEmpty ? nil : query)
                completion(list.map(mapDTOToCoupon))
            } catch {
                completion([])
            }
        }
    }

    func fetchApplicableCoupons(restaurantId: String, cartTotal: Double, city: String?,
                               completion: @escaping ([Coupon]) -> Void) {
        Task {
            do {
                var query: [URLQueryItem] = [
                    URLQueryItem(name: "restaurant_id", value: restaurantId),
                    URLQueryItem(name: "cart_total", value: String(cartTotal)),
                ]
                if let city, !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    query.append(URLQueryItem(name: "city", value: city.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
                let list = try await APIClient.shared.get([CouponDTO].self, path: "/coupons/public", queryItems: query)
                completion(list.map(mapDTOToCoupon))
            } catch {
                completion([])
            }
        }
    }

    // MARK: - Validation (stub)

    func validateCoupon(code: String, restaurantId: String?, cartTotal: Double, userId: String,
                        alreadyAppliedIds: [String] = [],
                        completion: @escaping (Result<Coupon, Error>) -> Void) {
        Task {
            do {
                let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard !normalizedCode.isEmpty else {
                    completion(.failure(CouponValidationError.notFound))
                    return
                }

                let queryItems: [URLQueryItem]? = {
                    guard let rid = restaurantId, !rid.isEmpty else { return nil }
                    return [URLQueryItem(name: "restaurant_id", value: rid)]
                }()

                let dto = try await APIClient.shared.get(
                    CouponDTO.self,
                    path: "/coupons/code/\(normalizedCode)",
                    queryItems: queryItems
                )
                let coupon = mapDTOToCoupon(dto)

                if alreadyAppliedIds.contains(coupon.id) {
                    completion(.failure(CouponValidationError.alreadyApplied))
                    return
                }
                if !coupon.isActive {
                    completion(.failure(CouponValidationError.inactive))
                    return
                }
                if coupon.isExpired {
                    completion(.failure(CouponValidationError.expired))
                    return
                }
                if let min = coupon.minCartTotal, cartTotal < min {
                    completion(.failure(CouponValidationError.minCartNotMet(min)))
                    return
                }
                if let rid = restaurantId,
                   let couponRid = coupon.restaurantId,
                   !couponRid.isEmpty,
                   couponRid != rid {
                    completion(.failure(CouponValidationError.wrongRestaurant))
                    return
                }

                completion(.success(coupon))
            } catch let apiError as APIError {
                switch apiError {
                case .notFound:
                    completion(.failure(CouponValidationError.notFound))
                case .serverError(let statusCode, let message):
                    let lower = message.lowercased()
                    if statusCode == 409 && lower.contains("süresi dol") {
                        completion(.failure(CouponValidationError.expired))
                    } else if statusCode == 409 && lower.contains("aktif değil") {
                        completion(.failure(CouponValidationError.inactive))
                    } else if statusCode == 409 && lower.contains("mağazada geçerli değil") {
                        completion(.failure(CouponValidationError.wrongRestaurant))
                    } else {
                        completion(.failure(apiError))
                    }
                default:
                    completion(.failure(apiError))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Usage Tracking (stub)

    func recordUsages(couponIds: [String], userId: String) { }

    // MARK: - Helpers

    private func fetchStoreCoupons(restaurantId: String) async throws -> [Coupon] {
        let response = try await APIClient.shared.get([CouponDTO].self, path: "/coupons/restaurant/\(restaurantId)")
        return response.map(mapDTOToCoupon)
    }

    private func mapDTOToCoupon(_ dto: CouponDTO) -> Coupon {
        let parsed = parseTitleAndDescription(dto.description)
        let discountType: DiscountType = dto.discountPercent > 0 ? .percentage : .fixed
        let discountValue: Double = discountType == .percentage ? dto.discountPercent : dto.discountAmount
        return Coupon(
            id: dto.id,
            code: dto.code,
            title: parsed.title,
            description: parsed.body,
            restaurantId: dto.restaurantId,
            restaurantName: dto.restaurantName,
            discountType: discountType,
            discountValue: discountValue,
            maxDiscountAmount: nil,
            minCartTotal: dto.minimumOrderAmount > 0 ? dto.minimumOrderAmount : nil,
            maxTotalUsage: nil,
            maxUsagePerUser: nil,
            isPublic: dto.isPublic,
            city: dto.city,
            isActive: dto.isActive,
            expiresAt: dto.expiryDate,
            usageCount: 0,
            createdAt: dto.createdAt ?? Date(),
            createdBy: ""
        )
    }

    private func toUpsertRequest(_ coupon: Coupon) -> CouponUpsertRequest {
        let cleanTitle = coupon.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = coupon.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let mergedDescription: String
        if cleanBody.isEmpty {
            mergedDescription = cleanTitle
        } else {
            mergedDescription = "\(cleanTitle) — \(cleanBody)"
        }

        let discountAmount = coupon.discountType == .fixed ? coupon.discountValue : 0
        let discountPercent = coupon.discountType == .percentage ? coupon.discountValue : 0

        return CouponUpsertRequest(
            id: coupon.id,
            restaurantId: coupon.restaurantId,
            code: coupon.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            description: mergedDescription,
            discountAmount: discountAmount,
            discountPercent: discountPercent,
            minimumOrderAmount: coupon.minCartTotal ?? 0,
            expiryDate: coupon.expiresAt,
            isActive: coupon.isActive,
            isPublic: coupon.isPublic,
            city: coupon.city
        )
    }

    private func parseTitleAndDescription(_ raw: String) -> (title: String, body: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ("Kupon", "")
        }

        if let range = trimmed.range(of: " — ") {
            let title = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let body = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (title.isEmpty ? "Kupon" : title, body)
        }

        return (trimmed, "")
    }
}
