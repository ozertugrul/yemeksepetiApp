import Foundation
import Combine

// MARK: - ListenerRegistration (replaces FirebaseFirestore.ListenerRegistration)

/// Drop-in replacement for Firestore's ListenerRegistration.
/// Uses a Timer to poll the backend at a fixed interval.
final class ListenerRegistration {
    private var timer: Timer?

    init(interval: TimeInterval, fireImmediately: Bool = true, action: @escaping () -> Void) {
        if fireImmediately { action() }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in action() }
    }

    func remove() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - OrderService

final class OrderService: ObservableObject {
    private let orderAPI = OrderAPIService()

    func placeOrder(_ order: Order, completion: @escaping (Result<Order, Error>) -> Void) {
        Task {
            do {
                let placed = try await orderAPI.placeOrder(order)
                DispatchQueue.main.async { completion(.success(placed)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func fetchUserOrders(userId: String, completion: @escaping ([Order]) -> Void) {
        Task {
            let orders = (try? await orderAPI.fetchMyOrders()) ?? []
            DispatchQueue.main.async { completion(orders) }
        }
    }

    func listenUserOrders(userId: String, onUpdate: @escaping ([Order]) -> Void) -> ListenerRegistration {
        ListenerRegistration(interval: 20) { [weak self] in
            guard let self else { return }
            Task {
                let orders = (try? await self.orderAPI.fetchMyOrders()) ?? []
                DispatchQueue.main.async { onUpdate(orders) }
            }
        }
    }

    func requestCancellation(orderId: String, reason: String, completion: @escaping (Error?) -> Void) {
        DispatchQueue.main.async { completion(nil) }
    }

    func handleCancelRequest(orderId: String, approve: Bool, completion: @escaping (Error?) -> Void) {
        if approve { updateOrderStatus(orderId: orderId, status: .cancelled, completion: completion) }
        else { DispatchQueue.main.async { completion(nil) } }
    }

    func cancelOrder(orderId: String, completion: @escaping (Error?) -> Void) {
        updateOrderStatus(orderId: orderId, status: .cancelled, completion: completion)
    }

    func fetchRestaurantOrders(restaurantId: String, completion: @escaping ([Order]) -> Void) {
        Task {
            let orders = (try? await orderAPI.fetchRestaurantOrders(restaurantId: restaurantId)) ?? []
            DispatchQueue.main.async { completion(orders) }
        }
    }

    func listenRestaurantOrders(restaurantId: String, onUpdate: @escaping ([Order]) -> Void) -> ListenerRegistration {
        ListenerRegistration(interval: 15) { [weak self] in
            guard let self else { return }
            Task {
                let orders = (try? await self.orderAPI.fetchRestaurantOrders(restaurantId: restaurantId)) ?? []
                DispatchQueue.main.async { onUpdate(orders) }
            }
        }
    }

    func updateOrderStatus(orderId: String, status: OrderStatus, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                _ = try await orderAPI.updateStatus(orderId: orderId, status: status)
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
    }

    func submitReview(_ review: OrderReview, restaurant: Restaurant, completion: @escaping (Error?) -> Void) {
        DispatchQueue.main.async { completion(nil) }
    }

    func fetchReviews(restaurantId: String, completion: @escaping ([OrderReview]) -> Void) {
        DispatchQueue.main.async { completion([]) }
    }

    func incrementSuccessfulOrders(restaurantId: String) { }

    func fetchSalesData(restaurantId: String, from startDate: Date, to endDate: Date, completion: @escaping ([Order]) -> Void) {
        Task {
            let all = (try? await orderAPI.fetchRestaurantOrders(restaurantId: restaurantId)) ?? []
            let filtered = all.filter { $0.status == .completed && $0.createdAt >= startDate && $0.createdAt <= endDate }
                              .sorted { $0.createdAt > $1.createdAt }
            DispatchQueue.main.async { completion(filtered) }
        }
    }
}
