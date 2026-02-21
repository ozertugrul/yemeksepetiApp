import SwiftUI

// MARK: - UserCouponsView

struct UserCouponsView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var coupons: [Coupon] = []
    @State private var isLoading = true

    private var userCity: String? {
        let city = viewModel.authService.currentUser?.city
        return (city?.isEmpty == false) ? city : nil
    }

    // Genel kuponlar (restaurantId yok)
    private var generalCoupons: [Coupon] { coupons.filter { $0.restaurantId == nil } }
    // Mağazaya özel public kuponlar
    private var storeCoupons: [Coupon]   { coupons.filter { $0.restaurantId != nil } }

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Kuponlar yükleniyor...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if coupons.isEmpty {
                    emptyState
                } else {
                    couponList
                }
            }
            .navigationTitle("Kuponlarım")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { load() } label: {
                        Image(systemName: "arrow.clockwise").foregroundColor(.orange)
                    }
                }
            }
        }
        .onAppear { load() }
    }

    // MARK: - List

    private var couponList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !generalCoupons.isEmpty {
                    sectionHeader("🎁 Genel Kuponlar")
                    ForEach(generalCoupons) { coupon in
                        UserCouponCard(coupon: coupon).padding(.horizontal).padding(.bottom, 10)
                    }
                }
                if !storeCoupons.isEmpty {
                    sectionHeader("🏪 Mağazaya Özel Kuponlar")
                    ForEach(storeCoupons) { coupon in
                        UserCouponCard(coupon: coupon).padding(.horizontal).padding(.bottom, 10)
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.subheadline).fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal).padding(.vertical, 6)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "ticket").font(.system(size: 60)).foregroundColor(.orange.opacity(0.4))
            Text("Şu an kupon yok").font(.title3).fontWeight(.semibold)
            Text(userCity != nil
                 ? "\(userCity!) şehri için geçerli herkese açık kupon bulunamadı."
                 : "Profilinize şehir ekleyerek size özel kuponları görebilirsiniz.")
                .multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)
            Spacer()
        }
    }

    // MARK: - Load

    private func load() {
        isLoading = true
        viewModel.couponService.fetchPublicCoupons(city: userCity) { fetched in
            coupons = fetched
            isLoading = false
        }
    }
}

// MARK: - UserCouponCard

struct UserCouponCard: View {
    let coupon: Coupon
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(coupon.title).font(.headline)
                    if !coupon.description.isEmpty {
                        Text(coupon.description).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                // Discount pill
                Text(coupon.discountLabel)
                    .font(.caption).fontWeight(.bold).foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.orange).cornerRadius(8)
            }

            // Store info (mağazaya özgü ise)
            if let storeName = coupon.restaurantName {
                Label(storeName, systemImage: "storefront").font(.caption).foregroundColor(.secondary)
            }

            // Conditions
            HStack(spacing: 12) {
                if let min = coupon.minCartTotal {
                    Label("Min. ₺\(String(format: "%.0f", min))", systemImage: "cart")
                        .font(.caption2).foregroundColor(.secondary)
                }
                if let max = coupon.maxTotalUsage {
                    Label("\(max - coupon.usageCount) kalan", systemImage: "tag")
                        .font(.caption2).foregroundColor(.secondary)
                }
                if let exp = coupon.expiresAt {
                    Label(formatDate(exp), systemImage: "calendar")
                        .font(.caption2).foregroundColor(coupon.isExpired ? .red : .secondary)
                }
            }

            // Code row + copy button
            HStack(spacing: 8) {
                Text(coupon.code)
                    .font(.system(.body, design: .monospaced)).fontWeight(.bold)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                Spacer()
                Button {
                    UIPasteboard.general.string = coupon.code
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Kopyalandı" : "Kodu Kopyala")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(copied ? Color.green : Color.orange)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "dd MMM yyyy"
        return f.string(from: date)
    }
}
