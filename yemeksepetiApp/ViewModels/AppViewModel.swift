import Foundation
import Combine

class AppViewModel: ObservableObject {
    @Published var authService = AuthService()
    @Published var dataService = DataService()
    @Published var cart = CartViewModel()
    @Published var orderService = OrderService()
    @Published var couponService = CouponService()
    @Published var selectedTab: Int = 0

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
        authService.$currentUser
            .sink { [weak self] user in
                guard let self else { return }
                let newId = user?.id
                if newId != self.lastUserId {
                    // User logged out (nil) or switched to a different account
                    self.cart.clear()
                }
                self.lastUserId = newId
            }
            .store(in: &cancellables)
    }

    // Helper to check if current user is admin
    var isAdmin: Bool {
        return authService.userRole == .superAdmin
    }

    // Helper to check if current user is store owner
    var isStoreOwner: Bool {
        return authService.userRole == .storeOwner
    }
}

