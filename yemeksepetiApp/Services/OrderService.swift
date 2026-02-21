import Foundation
import FirebaseFirestore
import Combine

final class OrderService: ObservableObject {
    private let db = Firestore.firestore()
    private let ordersCollection = "orders"
    private let reviewsCollection = "reviews"
    private var listeners: [ListenerRegistration] = []
    private let orderAPI = OrderAPIService()

    deinit { listeners.forEach { $0.remove() } }

    // MARK: - Place Order

    func placeOrder(_ order: Order, completion: @escaping (Result<Order, Error>) -> Void) {
        guard !APIConfig.useSQLBackend else {
            Task {
                do {
                    let placed = try await orderAPI.placeOrder(order)
                    DispatchQueue.main.async { completion(.success(placed)) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
            return
        }
        do {
            try db.collection(ordersCollection).document(order.id).setData(from: order) { error in
                DispatchQueue.main.async {
                    if let error { completion(.failure(error)) }
                    else { completion(.success(order)) }
                }
            }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }

    // MARK: - Fetch User Orders (one-shot)

    func fetchUserOrders(userId: String, completion: @escaping ([Order]) -> Void) {
        guard !APIConfig.useSQLBackend else {
            Task {
                do {
                    let orders = try await orderAPI.fetchMyOrders()
                    DispatchQueue.main.async { completion(orders) }
                } catch {
                    print("[OrderService] API fetchUserOrders hata: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion([]) }
                }
            }
            return
        }
        db.collection(ordersCollection)
            .whereField("userId", isEqualTo: userId)
            .getDocuments { snapshot, _ in
                let orders = (snapshot?.documents.compactMap { try? $0.data(as: Order.self) } ?? [])
                    .sorted { $0.createdAt > $1.createdAt }
                DispatchQueue.main.async { completion(orders) }
            }
    }

    // MARK: - Listen User Orders (real-time)

    func listenUserOrders(userId: String, onUpdate: @escaping ([Order]) -> Void) -> ListenerRegistration {
        let listener = db.collection(ordersCollection)
            .whereField("userId", isEqualTo: userId)
            .addSnapshotListener { snapshot, _ in
                let orders = (snapshot?.documents.compactMap { try? $0.data(as: Order.self) } ?? [])
                    .sorted { $0.createdAt > $1.createdAt }
                DispatchQueue.main.async { onUpdate(orders) }
            }
        listeners.append(listener)
        return listener
    }

    // MARK: - Request Cancellation (user side)
    // Writes only the cancel-request fields — allowed by Firestore rules for the order owner.
    func requestCancellation(orderId: String, reason: String, completion: @escaping (Error?) -> Void) {
        db.collection(ordersCollection).document(orderId).updateData([
            "cancelRequested": true,
            "cancelReason": reason,
            "cancelRequestedAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ]) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    // MARK: - Handle Cancel Request (owner side)
    // approve = true  → set status = cancelled, clear the request flags
    // approve = false → just clear the request flags (rejected by owner)
    func handleCancelRequest(orderId: String, approve: Bool, completion: @escaping (Error?) -> Void) {
        var data: [String: Any] = [
            "cancelRequested": false,
            "cancelReason": "",
            "cancelRequestedAt": NSNull(),
            "updatedAt": Timestamp(date: Date())
        ]
        if approve { data["status"] = OrderStatus.cancelled.rawValue }
        db.collection(ordersCollection).document(orderId).updateData(data) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    // MARK: - Cancel Order (kept for backwards compat / admin use)

    func cancelOrder(orderId: String, completion: @escaping (Error?) -> Void) {
        updateOrderStatus(orderId: orderId, status: .cancelled, completion: completion)
    }

    // MARK: - Fetch Restaurant Orders

    func fetchRestaurantOrders(restaurantId: String, completion: @escaping ([Order]) -> Void) {
        guard !APIConfig.useSQLBackend else {
            Task {
                do {
                    let orders = try await orderAPI.fetchRestaurantOrders(restaurantId: restaurantId)
                    DispatchQueue.main.async { completion(orders) }
                } catch {
                    print("[OrderService] API fetchRestaurantOrders hata: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion([]) }
                }
            }
            return
        }
        // No .order(by:) — avoids composite index requirement. Sort client-side.
        db.collection(ordersCollection)
            .whereField("restaurantId", isEqualTo: restaurantId)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("[OrderService] fetchRestaurantOrders error: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion([]) }; return
                }
                let orders = (snapshot?.documents.compactMap { try? $0.data(as: Order.self) } ?? [])
                    .sorted { $0.createdAt > $1.createdAt }
                DispatchQueue.main.async { completion(orders) }
            }
    }

    // MARK: - Listen Restaurant Orders (real-time)

    func listenRestaurantOrders(
        restaurantId: String,
        onUpdate: @escaping ([Order]) -> Void
    ) -> ListenerRegistration {
        // Note: No .order(by:) here — combining whereField + order(by) requires a
        // Firestore composite index. We sort client-side to avoid silent failures.
        let listener = db.collection(ordersCollection)
            .whereField("restaurantId", isEqualTo: restaurantId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("[OrderService] listenRestaurantOrders error: \(error.localizedDescription)")
                    return
                }
                let orders = (snapshot?.documents.compactMap { try? $0.data(as: Order.self) } ?? [])
                    .sorted { $0.createdAt > $1.createdAt }
                DispatchQueue.main.async { onUpdate(orders) }
            }
        listeners.append(listener)
        return listener
    }

    // MARK: - Update Order Status

    func updateOrderStatus(
        orderId: String,
        status: OrderStatus,
        completion: @escaping (Error?) -> Void
    ) {
        guard !APIConfig.useSQLBackend else {
            Task {
                do {
                    _ = try await orderAPI.updateStatus(orderId: orderId, status: status)
                    DispatchQueue.main.async { completion(nil) }
                } catch {
                    DispatchQueue.main.async { completion(error) }
                }
            }
            return
        }
        db.collection(ordersCollection).document(orderId).updateData([
            "status": status.rawValue,
            "updatedAt": Timestamp(date: Date())
        ]) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    // MARK: - Submit Review

    func submitReview(_ review: OrderReview, restaurant: Restaurant, completion: @escaping (Error?) -> Void) {
        do {
            try db.collection(reviewsCollection).document(review.id).setData(from: review) { [weak self] error in
                if let error { DispatchQueue.main.async { completion(error) }; return }
                // Call success immediately — the review is persisted
                DispatchQueue.main.async { completion(nil) }
                // Mark order as reviewed (fire-and-forget, non-critical)
                self?.db.collection("orders").document(review.orderId).updateData(["isReviewed": true])
                // Update restaurant aggregate rating (fire-and-forget — customer may not have
                // write permission on the restaurant doc; failure is non-fatal)
                self?.updateRestaurantRating(restaurantId: review.restaurantId, newRating: review.averageRating) { error in
                    if let error {
                        print("[OrderService] updateRestaurantRating non-fatal error: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            DispatchQueue.main.async { completion(error) }
        }
    }

    private func updateRestaurantRating(restaurantId: String, newRating: Double, completion: @escaping (Error?) -> Void) {
        let ref = db.collection("restaurants").document(restaurantId)
        db.runTransaction({ transaction, _ in
            guard let snap = try? transaction.getDocument(ref),
                  let data = snap.data() else { return nil }
            let count = (data["ratingCount"] as? Int ?? 0) + 1
            let current = (data["averageRating"] as? Double ?? 0)
            let newAvg = ((current * Double(count - 1)) + newRating) / Double(count)
            let successCount = (data["successfulOrderCount"] as? Int ?? 0) + 1
            transaction.updateData([
                "ratingCount": count,
                "averageRating": newAvg,
                "successfulOrderCount": successCount
            ], forDocument: ref)
            return nil
        }) { _, error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    // MARK: - Increment Successful Order Count (when order is completed, before review)

    func incrementSuccessfulOrders(restaurantId: String) {
        db.collection("restaurants").document(restaurantId).updateData([
            "successfulOrderCount": FieldValue.increment(Int64(1))
        ])
    }

    // MARK: - Fetch Reviews for Restaurant

    func fetchReviews(restaurantId: String, completion: @escaping ([OrderReview]) -> Void) {
        // No .order(by:) — avoids composite index requirement. Sort client-side.
        db.collection(reviewsCollection)
            .whereField("restaurantId", isEqualTo: restaurantId)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("[OrderService] fetchReviews error: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion([]) }; return
                }
                let reviews = (snapshot?.documents.compactMap { try? $0.data(as: OrderReview.self) } ?? [])
                    .sorted { $0.createdAt > $1.createdAt }
                DispatchQueue.main.async { completion(reviews) }
            }
    }

    // MARK: - Sales Data (for owner reports)

    func fetchSalesData(
        restaurantId: String,
        from startDate: Date,
        to endDate: Date,
        completion: @escaping ([Order]) -> Void
    ) {
        // Only filter by restaurantId to avoid composite index requirement.
        // Status + date filtering is done client-side.
        db.collection(ordersCollection)
            .whereField("restaurantId", isEqualTo: restaurantId)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("[OrderService] fetchSalesData error: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion([]) }; return
                }
                let all = snapshot?.documents.compactMap { try? $0.data(as: Order.self) } ?? []
                let filtered = all.filter { order in
                    order.status == .completed &&
                    order.createdAt >= startDate &&
                    order.createdAt <= endDate
                }
                    .sorted { $0.createdAt > $1.createdAt }
                DispatchQueue.main.async { completion(filtered) }
            }
    }
}
