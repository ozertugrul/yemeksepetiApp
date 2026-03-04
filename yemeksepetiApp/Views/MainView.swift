import SwiftUI

struct MainView: View {
    @ObservedObject var appViewModel: AppViewModel

    private var role: UserRole { appViewModel.authService.userRole }
    private var isAuth: Bool { appViewModel.authService.isAuthenticated }

    var body: some View {
        Group {
            // Store owners and admins only see their own dashboard — no customer UI
            if isAuth && (role == .storeOwner || role == .superAdmin) {
                NavigationView {
                    if role == .superAdmin {
                        AdminDashboardView(viewModel: appViewModel)
                    } else {
                        StoreDashboardView(viewModel: appViewModel)
                    }
                }
                .tint(.orange)
                .subtleCardTransition()
            } else {
                // Customer / unauthenticated: full tab bar
                TabView(selection: $appViewModel.selectedTab) {
                    // Tab 0: Home
                    HomeView(viewModel: appViewModel)
                        .tabItem { Label("Ana Sayfa", systemImage: "house.fill") }
                        .tag(0)

                // Tab 1: Search
                SearchView(viewModel: appViewModel)
                    .tabItem { Label("Ara", systemImage: "magnifyingglass") }
                    .tag(1)

                // Tab 2: Cart
                CartView(cart: appViewModel.cart, viewModel: appViewModel)
                    .tabItem { Label("Sepet", systemImage: "cart.fill") }
                    .tag(2)
                    .badge(appViewModel.cart.itemCount > 0 ? "\(appViewModel.cart.itemCount)" : nil)

                // Tab 3: Kuponlarım
                UserCouponsView(viewModel: appViewModel)
                    .tabItem { Label("Kuponlarım", systemImage: "ticket.fill") }
                    .tag(3)

                // Tab 4: Profile / Login
                NavigationView {
                    if isAuth && !appViewModel.authService.isGuest {
                        UserProfileView(viewModel: appViewModel)
                    } else {
                        GuestLoginScreen(viewModel: appViewModel, context: .profile)
                    }
                }
                    .tabItem {
                        Label(isAuth && !appViewModel.authService.isGuest ? "Hesabım" : "Giriş Yap", systemImage: "person.circle.fill")
                    }
                    .tag(4)
                }
                .tint(.orange)
                .animation(AppMotion.quick, value: appViewModel.selectedTab)
                .subtleCardTransition()
            }
        }
        .animation(AppMotion.standard, value: isAuth)
        .animation(AppMotion.standard, value: role)
    }
}

