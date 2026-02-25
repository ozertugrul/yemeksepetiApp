import SwiftUI

struct AdminDashboardView: View {
    @ObservedObject var viewModel: AppViewModel
    /// Tüm admin sekmelerinin tek veri kaynağı; bu View tarafından sahiplenilir.
    @StateObject private var adminVM: AdminViewModel

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        // AdminViewModel'i adminAPI referansıyla oluştur
        _adminVM = StateObject(
            wrappedValue: AdminViewModel(api: viewModel.adminAPI)
        )
    }

    var body: some View {
        TabView {
            AdminUserListView(viewModel: viewModel, adminVM: adminVM)
                .tabItem {
                    Label("Kullanıcılar", systemImage: "person.3")
                }

            AdminRestaurantListView(viewModel: viewModel, adminVM: adminVM)
                .tabItem {
                    Label("Restoranlar", systemImage: "building.2")
                }

            AdminStatsView(adminVM: adminVM)
                .tabItem {
                    Label("İstatistikler", systemImage: "chart.bar")
                }
        }
        .navigationTitle("Admin Paneli")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.authService.signOut()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundColor(.red)
                }
            }
        }
        .onAppear {
            // İlk açılışta tüm sekmelerin verilerini paralel başlat
            if adminVM.users.isEmpty        { adminVM.reloadUsers() }
            if adminVM.restaurants.isEmpty  { adminVM.reloadRestaurants() }
            adminVM.loadStats()
        }
    }
}
