import SwiftUI
import FirebaseFirestore

// MARK: - OwnerCouponsView

struct OwnerCouponsView: View {
    let restaurant: Restaurant
    @ObservedObject var viewModel: AppViewModel

    @State private var coupons: [Coupon] = []
    @State private var listenerReg: ListenerRegistration?
    @State private var isLoading = true
    @State private var showingCreate = false
    @State private var editingCoupon: Coupon?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer(); ProgressView("Yükleniyor..."); Spacer()
            } else if coupons.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(coupons) { coupon in
                            CouponCard(
                                coupon: coupon,
                                onToggleActive: { toggleActive(coupon) },
                                onTogglePublic: { togglePublic(coupon) },
                                onEdit:   { editingCoupon = coupon },
                                onDelete: { deleteCoupon(coupon) }
                            )
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
        }
        .navigationTitle("Kuponlar")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingCreate = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3).foregroundColor(.orange)
                }
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateCouponView(restaurantId: restaurant.id,
                             restaurantName: restaurant.name,
                             restaurantCity: restaurant.city,
                             createdBy: viewModel.authService.currentUser?.id ?? "",
                             couponService: viewModel.couponService,
                             existingCoupon: nil) { _ in
                showingCreate = false
            }
        }
        .sheet(item: $editingCoupon) { coupon in
            CreateCouponView(restaurantId: restaurant.id,
                             restaurantName: restaurant.name,
                             restaurantCity: restaurant.city,
                             createdBy: viewModel.authService.currentUser?.id ?? "",
                             couponService: viewModel.couponService,
                             existingCoupon: coupon) { _ in
                editingCoupon = nil
            }
        }
        .alert("Hata", isPresented: .constant(errorMessage != nil)) {
            Button("Tamam") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .onAppear { startListening() }
        .onDisappear { listenerReg?.remove() }
    }

    // MARK: Empty State
    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "ticket").font(.system(size: 56)).foregroundColor(.orange.opacity(0.4))
            Text("Henüz Kupon Yok").font(.title3).fontWeight(.semibold)
            Text("Müşterilere özel kupon oluşturun ve satışlarınızı artırın.")
                .multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)
            Button { showingCreate = true } label: {
                Label("Kupon Oluştur", systemImage: "plus.circle.fill")
                    .font(.headline).foregroundColor(.white)
                    .padding().frame(maxWidth: .infinity)
                    .background(Color.orange).cornerRadius(14)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
    }

    // MARK: Listener
    private func startListening() {
        isLoading = true
        listenerReg?.remove()
        listenerReg = viewModel.couponService.listenStoreCoupons(restaurantId: restaurant.id) { fetched in
            coupons = fetched
            isLoading = false
        }
    }

    // MARK: Actions
    private func toggleActive(_ coupon: Coupon) {
        var updated = coupon; updated.isActive.toggle()
        viewModel.couponService.updateCoupon(updated) { if let e = $0 { errorMessage = e.localizedDescription } }
    }
    private func togglePublic(_ coupon: Coupon) {
        var updated = coupon; updated.isPublic.toggle()
        viewModel.couponService.updateCoupon(updated) { if let e = $0 { errorMessage = e.localizedDescription } }
    }
    private func deleteCoupon(_ coupon: Coupon) {
        viewModel.couponService.deleteCoupon(coupon.id) { if let e = $0 { errorMessage = e.localizedDescription } }
    }
}

// MARK: - CouponCard

private struct CouponCard: View {
    let coupon: Coupon
    let onToggleActive: () -> Void
    let onTogglePublic: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    private var statusColor: Color {
        if !coupon.isActive { return .gray }
        if coupon.isExpired  { return .red }
        return .green
    }
    private var statusLabel: String {
        if !coupon.isActive { return "Pasif" }
        if coupon.isExpired  { return "Süresi Doldu" }
        return "Aktif"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(spacing: 8) {
                // Code badge
                Text(coupon.code)
                    .font(.system(.subheadline, design: .monospaced)).fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.orange).cornerRadius(8)

                Text(coupon.title).font(.subheadline).fontWeight(.semibold).lineLimit(1)
                Spacer()
                // Status pill
                Text(statusLabel)
                    .font(.caption2).fontWeight(.bold).foregroundColor(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(statusColor).cornerRadius(6)
            }

            // Discount description
            HStack(spacing: 6) {
                Image(systemName: coupon.discountType == .percentage ? "percent" : "turkishlirasign")
                    .font(.caption).foregroundColor(.orange)
                Text(coupon.discountLabel).font(.caption).foregroundColor(.secondary)
            }

            // Conditions
            if let min = coupon.minCartTotal {
                Label("Min. ₺\(String(format: "%.2f", min)) sepet tutarı", systemImage: "cart")
                    .font(.caption2).foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                if let maxTotal = coupon.maxTotalUsage {
                    Label("\(coupon.usageCount)/\(maxTotal) kullanım", systemImage: "person.2")
                        .font(.caption2).foregroundColor(.secondary)
                }
                if let exp = coupon.expiresAt {
                    Label(formatDate(exp), systemImage: "calendar.badge.clock")
                        .font(.caption2).foregroundColor(coupon.isExpired ? .red : .secondary)
                }
            }

            Divider()

            // Toggle row
            HStack(spacing: 0) {
                // Active toggle
                Button(action: onToggleActive) {
                    Label(coupon.isActive ? "Aktif" : "Pasif",
                          systemImage: coupon.isActive ? "checkmark.circle.fill" : "pause.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(coupon.isActive ? .green : .gray)
                }
                .buttonStyle(.plain)

                Spacer()

                // Public toggle
                Button(action: onTogglePublic) {
                    Label(coupon.isPublic ? "Herkese Açık" : "Gizli",
                          systemImage: coupon.isPublic ? "eye.fill" : "eye.slash")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(coupon.isPublic ? .blue : .secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                // Edit
                Button(action: onEdit) {
                    Image(systemName: "pencil").font(.caption).foregroundColor(.orange)
                }
                .buttonStyle(.plain).padding(.horizontal, 8)

                // Delete
                Button { showDeleteConfirm = true } label: {
                    Image(systemName: "trash").font(.caption).foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .confirmationDialog("Kuponu silmek istediğinize emin misiniz?",
                                    isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                    Button("Sil", role: .destructive, action: onDelete)
                    Button("İptal", role: .cancel) {}
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "dd MMM yyyy"
        return f.string(from: date)
    }
}
