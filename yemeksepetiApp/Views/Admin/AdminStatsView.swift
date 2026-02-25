import SwiftUI

struct AdminStatsView: View {
    @ObservedObject var adminVM: AdminViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if adminVM.isLoadingStats && adminVM.stats == nil {
                    ProgressView("İstatistikler yükleniyor...")
                        .padding(.top, 60)
                } else if let msg = adminVM.statsError, adminVM.stats == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40)).foregroundColor(.orange)
                        Text(msg).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                        Button("Tekrar Dene") { adminVM.loadStats(forceRefresh: true) }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 60)
                } else if let s = adminVM.stats {
                    // ── Kullanıcılar ─────────────────────────────────────────
                    SectionHeader(title: "Kullanıcılar")
                    HStack(spacing: 16) {
                        StatCard(title: "Toplam Kullanıcı", value: "\(s.totalUsers)",
                                 icon: "person.3.fill", color: .blue)
                        StatCard(title: "Mağaza Sahibi", value: "\(s.storeOwnerCount)",
                                 icon: "storefront.fill", color: .orange)
                    }

                    // ── Restoranlar ───────────────────────────────────────────
                    SectionHeader(title: "Restoranlar")
                    HStack(spacing: 16) {
                        StatCard(title: "Toplam Mağaza", value: "\(s.totalRestaurants)",
                                 icon: "building.2.crop.circle", color: .indigo)
                        StatCard(title: "Aktif Mağaza", value: "\(s.activeRestaurants)",
                                 icon: "checkmark.circle.fill", color: .green)
                    }

                    // ── Siparişler ────────────────────────────────────────────
                    SectionHeader(title: "Siparişler")
                    HStack(spacing: 16) {
                        StatCard(title: "Bugünkü Sipariş", value: "\(s.todayOrders)",
                                 icon: "cart.badge.plus", color: .purple)
                        StatCard(title: "Toplam Sipariş", value: "\(s.totalOrders)",
                                 icon: "cart.fill", color: .teal)
                    }
                } else {
                    Color.clear.onAppear { adminVM.loadStats() }
                }
            }
            .padding()
        }
        .navigationTitle("İstatistikler")
        .onAppear { adminVM.loadStats() }
        .refreshable { adminVM.loadStats(forceRefresh: true) }
    }
}

// MARK: - SectionHeader

private struct SectionHeader: View {
    let title: String
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(color)
                    .padding(10)
                    .background(color.opacity(0.12))
                    .cornerRadius(10)
                Spacer()
            }
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.07), radius: 6, x: 0, y: 3)
    }
}
