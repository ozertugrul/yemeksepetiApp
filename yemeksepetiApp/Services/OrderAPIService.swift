import Foundation

// MARK: - API Response / Request Types

/// Backend 'OrderOut' response (camelCase JSON)
struct APIOrderOut: Decodable {
    var id: String
    var userId: String
    var restaurantId: String
    var restaurantName: String?
    var cancelRequested: Bool = false
    var cancelReason: String = ""
    var status: String
    var paymentMethod: String
    var deliveryAddress: APIDeliveryAddress?
    var items: [OrderItem]
    var subtotal: Double
    var deliveryFee: Double
    var discountAmount: Double
    var totalAmount: Double
    var couponCode: String?
    var notes: String?
    var isRated: Bool
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, userId, restaurantId, restaurantName
        case cancelRequested, cancelReason
        case status, paymentMethod, deliveryAddress, items
        case subtotal, deliveryFee, discountAmount, totalAmount
        case couponCode, notes, isRated, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        userId = try c.decode(String.self, forKey: .userId)
        restaurantId = try c.decode(String.self, forKey: .restaurantId)
        restaurantName = try c.decodeIfPresent(String.self, forKey: .restaurantName)
        cancelRequested = try c.decodeIfPresent(Bool.self, forKey: .cancelRequested) ?? false
        cancelReason = try c.decodeIfPresent(String.self, forKey: .cancelReason) ?? ""
        status = try c.decode(String.self, forKey: .status)
        paymentMethod = try c.decode(String.self, forKey: .paymentMethod)
        deliveryAddress = try c.decodeIfPresent(APIDeliveryAddress.self, forKey: .deliveryAddress)
        items = try c.decode([OrderItem].self, forKey: .items)
        subtotal = try c.decode(Double.self, forKey: .subtotal)
        deliveryFee = try c.decode(Double.self, forKey: .deliveryFee)
        discountAmount = try c.decode(Double.self, forKey: .discountAmount)
        totalAmount = try c.decode(Double.self, forKey: .totalAmount)
        couponCode = try c.decodeIfPresent(String.self, forKey: .couponCode)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        isRated = try c.decode(Bool.self, forKey: .isRated)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    /// Backend'den gelen Order'ı iOS modeline dönüştür
    func toOrder(restaurantName fallbackName: String = "") -> Order {
        let status = OrderStatus(rawValue: self.status) ?? .pending
        let method = PaymentMethod(rawValue: self.paymentMethod) ?? .cashOnDelivery
        // Önce backend'den gelen adı kullan, sonra fallback, son çare restaurantId
        let resolvedName: String
        if let n = self.restaurantName, !n.isEmpty {
            resolvedName = n
        } else if !fallbackName.isEmpty {
            resolvedName = fallbackName
        } else {
            resolvedName = restaurantId
        }
        return Order(
            id: id,
            restaurantId: restaurantId,
            restaurantName: resolvedName,
            userId: userId,
            userEmail: "",
            items: items,
            subtotal: subtotal,
            deliveryFee: deliveryFee,
            total: totalAmount,
            status: status,
            paymentMethod: method,
            deliveryAddress: deliveryAddress?.toUserAddress(),
            note: notes,
            createdAt: createdAt ?? Date(),
            updatedAt: createdAt ?? Date(),
            isReviewed: isRated,
            cancelRequested: cancelRequested,
            cancelReason: cancelReason,
            discountAmount: discountAmount
        )
    }
}

/// Teslimat adresi (backend snake_case JSON'dan gelir)
struct APIDeliveryAddress: Decodable {
    var title: String?
    var city: String?
    var district: String?
    var neighborhood: String?
    var street: String?
    var buildingNo: String?
    var flatNo: String?
    var directions: String?
    var isDefault: Bool?
    var phone: String?

    enum CodingKeys: String, CodingKey {
        case title, city, district, neighborhood, street, directions, phone
        // camelCase (iOS gönderim) için
        case buildingNo, flatNo, isDefault
        // snake_case (DB'den dönüş) için
        case building_no, flat_no, is_default
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try? c.decode(String.self, forKey: .title)
        city = try? c.decode(String.self, forKey: .city)
        district = try? c.decode(String.self, forKey: .district)
        neighborhood = try? c.decode(String.self, forKey: .neighborhood)
        street = try? c.decode(String.self, forKey: .street)
        directions = try? c.decode(String.self, forKey: .directions)
        phone = try? c.decode(String.self, forKey: .phone)
        buildingNo = (try? c.decode(String.self, forKey: .buildingNo))
            ?? (try? c.decode(String.self, forKey: .building_no))
        flatNo = (try? c.decode(String.self, forKey: .flatNo))
            ?? (try? c.decode(String.self, forKey: .flat_no))
        isDefault = (try? c.decode(Bool.self, forKey: .isDefault))
            ?? (try? c.decode(Bool.self, forKey: .is_default))
    }

    func toUserAddress() -> UserAddress {
        UserAddress(
            title: title ?? "Adres",
            city: city ?? "",
            district: district ?? "",
            neighborhood: neighborhood ?? "",
            street: street ?? "",
            buildingNo: buildingNo ?? "",
            flatNo: flatNo ?? "",
            directions: directions ?? "",
            isDefault: isDefault ?? false,
            phone: phone ?? ""
        )
    }
}

/// POST /orders request body
private struct OrderCreateBody: Encodable {
    var restaurantId: String
    var paymentMethod: String
    var deliveryAddress: DeliveryAddressBody?
    var items: [OrderItem]
    var subtotal: Double
    var deliveryFee: Double
    var discountAmount: Double
    var totalAmount: Double
    var couponCode: String?
    var notes: String?
}

private struct DeliveryAddressBody: Encodable {
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
}

// MARK: - OrderAPIService

struct OrderAPIService {
    private let client = APIClient.shared

    private struct CancelRequestBody: Encodable { let reason: String }
    private struct CancelDecisionBody: Encodable { let approve: Bool }

    // ── Sipariş Oluştur ───────────────────────────────────────────────────────

    func placeOrder(_ order: Order) async throws -> Order {
        let addrBody: DeliveryAddressBody?
        if let a = order.deliveryAddress {
            addrBody = DeliveryAddressBody(
                title: a.title, city: a.city, district: a.district,
                neighborhood: a.neighborhood, street: a.street,
                buildingNo: a.buildingNo, flatNo: a.flatNo,
                directions: a.directions, isDefault: a.isDefault,
                phone: a.phone, latitude: a.latitude, longitude: a.longitude
            )
        } else {
            addrBody = nil
        }

        let body = OrderCreateBody(
            restaurantId: order.restaurantId,
            paymentMethod: order.paymentMethod.rawValue,
            deliveryAddress: addrBody,
            items: order.items,
            subtotal: order.subtotal,
            deliveryFee: order.deliveryFee,
            discountAmount: order.discountAmount,
            totalAmount: order.total,
            couponCode: order.appliedCoupons.first?.code,
            notes: order.note
        )

        let api = try await client.post(APIOrderOut.self, path: "/orders", encodable: body)
        return api.toOrder(restaurantName: order.restaurantName)
    }

    // ── Kullanıcı Siparişleri ─────────────────────────────────────────────────

    func fetchMyOrders() async throws -> [Order] {
        let api = try await client.get([APIOrderOut].self, path: "/orders/me")
        return api.map { $0.toOrder() }
    }

    // ── Restoran Siparişleri (owner / admin) ──────────────────────────────────

    func fetchRestaurantOrders(restaurantId: String) async throws -> [Order] {
        let api = try await client.get(
            [APIOrderOut].self,
            path: "/orders/restaurant/\(restaurantId)"
        )
        return api.map { $0.toOrder() }
    }

    // ── Sipariş Detayı ────────────────────────────────────────────────────────

    func fetchOrder(id: String) async throws -> Order {
        let api = try await client.get(APIOrderOut.self, path: "/orders/\(id)")
        return api.toOrder()
    }

    // ── Durum Güncelle (owner / admin) ────────────────────────────────────────

    func updateStatus(orderId: String, status: OrderStatus) async throws -> Order {
        struct StatusBody: Encodable { var status: String }
        let api = try await client.patch(
            APIOrderOut.self,
            path: "/orders/\(orderId)/status",
            encodable: StatusBody(status: status.rawValue)
        )
        return api.toOrder()
    }

    // ── Cancellation Request Workflow ───────────────────────────────────────

    func requestCancellation(orderId: String, reason: String) async throws -> Order {
        let api = try await client.post(
            APIOrderOut.self,
            path: "/orders/\(orderId)/cancel-request",
            encodable: CancelRequestBody(reason: reason)
        )
        return api.toOrder()
    }

    func decideCancellation(orderId: String, approve: Bool) async throws -> Order {
        let api = try await client.post(
            APIOrderOut.self,
            path: "/orders/\(orderId)/cancel-request/decision",
            encodable: CancelDecisionBody(approve: approve)
        )
        return api.toOrder()
    }
}
