import Foundation
import Combine

class AppViewModel: ObservableObject {
    @Published var authService = AuthService()
    @Published var dataService = DataService()
    @Published var cart = CartViewModel()
    @Published var orderService = OrderService()
    @Published var couponService = CouponService()
    @Published var selectedTab: Int = 0

    // ── API Servisler (SQL backend aktifken kullanılır) ───────────────────────
    let userAPI = UserAPIService()
    let restaurantAPI = RestaurantAPIService()
    let recommendationAPI = RecommendationService()
    let adminAPI = AdminAPIService()

    private var cancellables = Set<AnyCancellable>()
    /// Tracks the last known user ID to detect account switches
    private var lastUserId: String?

    init() {
        // Propagate changes from AuthService to AppViewModel
        authService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        cart.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Clear cart when user logs out or switches accounts
        authService.$user
            .sink { [weak self] user in
                guard let self else { return }
                let newId = user?.id
                if newId != self.lastUserId {
                    self.cart.clear()
                }
                self.lastUserId = newId
            }
            .store(in: &cancellables)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    var isAdmin: Bool { authService.user?.role == .superAdmin }
    var isStoreOwner: Bool { authService.user?.role == .storeOwner }

    // ── Admin: Kullanıcı yönetimi ─────────────────────────────────────────────

    func fetchAllUsers(completion: @escaping ([AppUser], String?) -> Void) {
        Task {
            do {
                let users = try await adminAPI.fetchAllUsers()
                DispatchQueue.main.async { completion(users, nil) }
            } catch {
                DispatchQueue.main.async { completion([], error.localizedDescription) }
            }
        }
    }

    func updateUserRole(uid: String, role: UserRole, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await adminAPI.updateUserRole(uid: uid, role: role)
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
    }

    func deleteUser(uid: String, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await adminAPI.deleteUser(uid: uid)
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { completion(error) }
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
                DispatchQueue.main.async { completion(user, nil) }
            } catch {
                DispatchQueue.main.async { completion(nil, error) }
            }
        }
    }

    func toggleRestaurantActive(id: String, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                _ = try await adminAPI.toggleRestaurantActive(id: id)
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
    }
}

