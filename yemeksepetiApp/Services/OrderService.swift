import Foundation
import Combine

// MARK: - ListenerRegistration (replaces FirebaseFirestore.ListenerRegistration)

/// Drop-in replacement for Firestore's ListenerRegistration.
/// Schedules a polling Timer on RunLoop.main so it fires regardless of which
/// thread created this object.
final class ListenerRegistration {
    private var timer: Timer?

    init(interval: TimeInterval, fireImmediately: Bool = true, action: @escaping () -> Void) {
        if fireImmediately { action() }
        // RunLoop.main ensures the timer fires even when created from a background Task
        let t = Timer(timeInterval: interval, repeats: true) { _ in action() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func remove() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - OrderService

/// Wraps OrderAPIService with callback-based APIs consumed by SwiftUI views.
/// @MainActor guarantees all completions run on the main thread without
/// sprinkling DispatchQueue.main.async at every call site.
@MainActor
final class OrderService: ObservableObject {
    private let orderAPI = OrderAPIService()

    // MARK: - Place Order

    func placeOrder(_ order: Order, completion: @escaping (Result<Order, Error>) -> Void) {
        Task {
            do {
                let placed = try await orderAPI.placeOrder(order)
                completion(.success(placed))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - User Orders

    func fetchUserOrders(userId: String, completion: @escaping ([Order]) -> Void) {
        Task {
            let orders = (try? await orderAPI.fetchMyOrders()) ?? []
            completion(orders)
        }
    }

    func listenUserOrders(userId: String, onUpdate: @escaping ([Order]) -> Void) -> ListenerRegistration {
        ListenerRegistration(interval: 20) { [weak self] in
            guard let self else { return }
            Task {
                let orders = (try? await self.orderAPI.fetchMyOrders()) ?? []
                onUpdate(orders)
            }
        }
    }

    // MARK: - Restaurant Orders (owner / admin)

    func fetchRestaurantOrders(restaurantId: String, completion: @escaping ([Order]) -> Void) {
        Task {
            let orders = (try? await orderAPI.fetchRestaurantOrders(restaurantId: restaurantId)) ?? []
            completion(orders)
        }
    }

    func listenRestaurantOrders(restaurantId: String, onUpdate: @escaping ([Order]) -> Void) -> ListenerRegistration {
        ListenerRegistration(interval: 15) { [weak self] in
            guard let self else { return }
            Task {
                let orders = (try? await self.orderAPI.fetchRestaurantOrders(restaurantId: restaurantId)) ?? []
                onUpdate(orders)
            }
        }
    }

    // MARK: - Status Updates

    func updateOrderStatus(orderId: String, status: OrderStatus, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                _ = try await orderAPI.updateStatus(orderId: orderId, status: status)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func cancelOrder(orderId: String, completion: @escaping (Error?) -> Void) {
        updateOrderStatus(orderId: orderId, status: .cancelled, completion: completion)
    }

    func handleCancelRequest(orderId: String, approve: Bool, completion: @escaping (Error?) -> Void) {
        if approve { cancelOrder(orderId: orderId, completion: completion) }
        else { completion(nil) }
    }

    // MARK: - Cancellation Request (stub — no backend endpoint yet)

    func requestCancellation(orderId: String, reason: String, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    // MARK: - Sales Report

    func fetchSalesData(restaurantId: String, from startDate: Date, to endDate: Date,
                        completion: @escaping ([Order]) -> Void) {
        Task {
            let all = (try? await orderAPI.fetchRestaurantOrders(restaurantId: restaurantId)) ?? []
            let filtered = all
                .filter { $0.status == .completed && $0.createdAt >= startDate && $0.createdAt <= endDate }
                .sorted { $0.createdAt > $1.createdAt }
            completion(filtered)
        }
    }

    // MARK: - Reviews (stub — no backend endpoint yet)

    func submitReview(_ review: OrderReview, restaurant: Restaurant, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    func fetchReviews(restaurantId: String, completion: @escaping ([OrderReview]) -> Void) {
        completion([])
    }

    // MARK: - No-op helpers kept for API compatibility

    func incrementSuccessfulOrders(restaurantId: String) { }
}
