import Foundation
import Combine

@MainActor
class AppViewModel: ObservableObject {
    @Published var authService = AuthService()
    @Published var cart = CartViewModel()
    let dataService    = DataService()
    let orderService   = OrderService()
    let couponService  = CouponService()
    @Published var selectedTab: Int = 0

    // ── API Services ──────────────────────────────────────────────────────────
    let userAPI           = UserAPIService()
    let restaurantAPI     = RestaurantAPIService()
    let recommendationAPI = RecommendationService()
    let adminAPI          = AdminAPIService()

    private var cancellables = Set<AnyCancellable>()
    private var lastUserId: String?

    init() {
        // Propagate child-service changes up to AppViewModel so SwiftUI re-renders
        authService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        cart.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        dataService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        orderService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Clear cart on logout or account switch
        authService.$user
            .sink { [weak self] user in
                guard let self else { return }
                let newId = user?.id
                if newId != self.lastUserId { self.cart.clear() }
                self.lastUserId = newId
            }
            .store(in: &cancellables)
    }

    // ── Convenience ───────────────────────────────────────────────────────────

    var isAdmin: Bool      { authService.user?.role == .superAdmin }
    var isStoreOwner: Bool { authService.user?.role == .storeOwner }

    // ── Admin: User management ────────────────────────────────────────────────

    func fetchAllUsers(completion: @escaping ([AppUser], String?) -> Void) {
        Task {
            do {
                let users = try await adminAPI.fetchAllUsers()
                completion(users, nil)
            } catch {
                completion([], error.localizedDescription)
            }
        }
    }

    func updateUserRole(uid: String, role: UserRole, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await adminAPI.updateUserRole(uid: uid, role: role)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func deleteUser(uid: String, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await adminAPI.deleteUser(uid: uid)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func createUser(email: String, password: String, displayName: String?,
                    role: UserRole, completion: @escaping (AppUser?, Error?) -> Void) {
        Task {
            do {
                let user = try await adminAPI.createUser(
                    email: email, password: password,
                    displayName: displayName, role: role
                )
                completion(user, nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    // ── Admin: Restaurant management ──────────────────────────────────────────

    func toggleRestaurantActive(id: String, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                _ = try await adminAPI.toggleRestaurantActive(id: id)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }
}
