import SwiftUI

struct AdminDashboardView: View {
    @ObservedObject var viewModel: AppViewModel
    
    var body: some View {
        TabView {
            AdminUserListView(viewModel: viewModel)
                .tabItem {
                    Label("Kullanıcılar", systemImage: "person.3")
                }
            
            AdminRestaurantListView(viewModel: viewModel)
                .tabItem {
                    Label("Restoranlar", systemImage: "building.2")
                }
            
            AdminStatsView(viewModel: viewModel)
                .tabItem {
                    Label("İstatistikler", systemImage: "chart.bar")
                }
        }
        .navigationTitle("Admin Paneli")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    viewModel.authService.signOut()
                }) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundColor(.red)
                }
            }
        }
    }
}
