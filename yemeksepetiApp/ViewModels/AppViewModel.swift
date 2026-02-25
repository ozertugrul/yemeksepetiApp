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
    /// Shared selected address ID — keeps checkout ↔ home in sync
    @Published var selectedAddressId: String?

    // ── API Services ──────────────────────────────────────────────────────────
    let userAPI           = UserAPIService()
    let restaurantAPI     = RestaurantAPIService()
    let recommendationAPI = RecommendationService()
    let adminAPI          = AdminAPIService()

    private var cancellables = Set<AnyCancellable>()
    private var lastUserId: String?

    init() {
        // Only propagate auth changes (login/logout/role) so the root view can switch tabs.
        // DataService / OrderService changes should NOT trigger full-app re-render;
        // they are read locally via callbacks / completion handlers.
        authService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        cart.objectWillChange
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

    func fetchUsersPage(offset: Int, limit: Int = 50, completion: @escaping (AdminUsersPage?, String?) -> Void) {
        Task {
            do {
                let page = try await adminAPI.fetchUsersPage(offset: offset, limit: limit)
                completion(page, nil)
            } catch {
                completion(nil, error.localizedDescription)
            }
        }
    }

    func loadCachedAdminUsers(maxAge: TimeInterval = 300) -> [AppUser] {
        adminAPI.loadCachedUsers(maxAge: maxAge)
    }

    func saveAdminUsersCache(_ users: [AppUser]) {
        adminAPI.saveUsersToCache(users)
    }

    func clearAdminUsersCache() {
        adminAPI.clearUsersCache()
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
