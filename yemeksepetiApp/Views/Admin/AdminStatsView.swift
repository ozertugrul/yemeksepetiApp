import SwiftUI

struct AdminStatsView: View {
    @ObservedObject var viewModel: AppViewModel
    
    // Stats state
    @State private var totalRestaurants = 0
    @State private var activeRestaurants = 0
    @State private var totalUsers = 0 // Mock, as fetching all users is expensive/not standard content
    
    var body: some View {
        ScrollView {
                VStack(spacing: 20) {
                    StatCard(title: "Toplam Restoran", value: "\(totalRestaurants)", icon: "building.2.crop.circle", color: .blue)
                    
                    StatCard(title: "Aktif Restoranlar", value: "\(activeRestaurants)", icon: "checkmark.circle", color: .green)
                    
                    StatCard(title: "Tahmini Kullanıcı", value: "150+", icon: "person.3.fill", color: .orange)
                    
                    StatCard(title: "Günlük Sipariş", value: "24", icon: "cart.fill", color: .purple)
                }
                .padding()
            }
            .navigationTitle("İstatistikler")
            .onAppear(perform: loadStats)
    }
    
    func loadStats() {
        let ds = DataService()
        ds.getAllRestaurantsForAdmin { restaurants in
            self.totalRestaurants = restaurants.count
            self.activeRestaurants = restaurants.filter { $0.isActive }.count
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(color)
                .padding()
                .background(color.opacity(0.1))
                .cornerRadius(12)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Text(value)
                    .font(.title).bold()
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}
