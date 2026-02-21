import SwiftUI

// MARK: - CartView

struct CartView: View {
    @ObservedObject var cart: CartViewModel
    @ObservedObject var viewModel: AppViewModel
    @State private var showingCheckout = false
    @State private var showingClearAlert = false
    @State private var showingLoginPrompt = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if cart.isEmpty {
                    emptyStateView
                } else {
                    cartContentView
                }
            }
            .navigationTitle("Sepetim")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !cart.isEmpty {
                        Button("Temizle") { showingClearAlert = true }
                            .foregroundColor(.red)
                    }
                }
            }
            .alert("Sepeti temizle", isPresented: $showingClearAlert) {
                Button("Temizle", role: .destructive) { cart.clear() }
                Button("İptal", role: .cancel) {}
            } message: {
                Text("Sepetteki tüm ürünler silinecek.")
            }
            .sheet(isPresented: $showingCheckout) {
                CheckoutView(cart: cart, viewModel: viewModel, onSuccess: {
                    showingCheckout = false
                    viewModel.selectedTab = 0
                })
            }
            .sheet(isPresented: $showingLoginPrompt) {
                NavigationView {
                    GuestLoginScreen(viewModel: viewModel, context: .checkout)
                }
            }
        }
    }

    // ── Empty State ───────────────────────────────────────────────────────

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "cart").font(.system(size: 64)).foregroundColor(.orange.opacity(0.4))
            Text("Sepetiniz boş").font(.title2).fontWeight(.semibold)
            Text("Mağazalardan ürün ekleyerek başlayın.").foregroundColor(.secondary)
            Spacer()
        }
    }

    // ── Cart Content ──────────────────────────────────────────────────────

    private var cartContentView: some View {
        VStack(spacing: 0) {
            // Restaurant name banner
            if let name = cart.restaurantName {
                HStack {
                    Image(systemName: "storefront.fill").foregroundColor(.orange)
                    Text(name).font(.subheadline).fontWeight(.semibold)
                    Spacer()
                }
                .padding(.horizontal).padding(.vertical, 10)
                .background(Color.orange.opacity(0.08))
            }

            // ── Scrollable content ─────────────────────────────────
            ScrollView {
                VStack(spacing: 10) {

                    // Items card
                    VStack(spacing: 0) {
                        ForEach(Array(cart.items.enumerated()), id: \.element.id) { idx, cartItem in
                            CartItemRow(cart: cart, cartItemId: cartItem.id)
                            if idx < cart.items.count - 1 {
                                Divider().padding(.leading, 84)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .background(Color(.systemBackground))
                    .cornerRadius(14)
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 2)

                    // Summary card
                    VStack(spacing: 0) {
                        summaryRow(title: "Ara Toplam",
                                   value: "₺\(String(format: "%.2f", cart.subtotal))",
                                   bold: false)
                        Divider().padding(.horizontal, 16)
                        summaryRow(title: "Teslimat Ücreti",
                                   value: cart.deliveryFee > 0
                                       ? "₺\(String(format: "%.2f", cart.deliveryFee))"
                                       : "Ücretsiz",
                                   valueColor: .green,
                                   bold: false)
                        Divider().padding(.horizontal, 16)
                        summaryRow(title: "Toplam",
                                   value: "₺\(String(format: "%.2f", cart.total))",
                                   valueColor: .orange,
                                   bold: true)
                    }
                    .background(Color(.systemBackground))
                    .cornerRadius(14)
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))

            // ── Checkout button ────────────────────────────────────
            VStack(spacing: 0) {
                Divider()
                Button {
                    if viewModel.authService.isGuest {
                        showingLoginPrompt = true
                    } else {
                        showingCheckout = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Siparişi Onayla")
                        Spacer()
                        Text("₺\(String(format: "%.2f", cart.total))")
                            .fontWeight(.bold)
                    }
                    .font(.headline).foregroundColor(.white)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(14)
                    .padding()
                }
            }
        }
    }

    private func summaryRow(title: String, value: String,
                             valueColor: Color = .primary, bold: Bool) -> some View {
        HStack {
            Text(title)
                .fontWeight(bold ? .bold : .regular)
            Spacer()
            Text(value)
                .fontWeight(bold ? .bold : .regular)
                .foregroundColor(valueColor)
                .font(bold ? .headline : .subheadline)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - CartItemRow

struct CartItemRow: View {
    @ObservedObject var cart: CartViewModel
    let cartItemId: String

    // Always read fresh from the live array — never uses a stale captured copy
    private var item: CartItem? { cart.items.first(where: { $0.id == cartItemId }) }

    var body: some View {
        Group {
            if let item {
                HStack(spacing: 12) {
                    // Image
                    if let urlString = item.menuItem.imageUrl, let url = URL(string: urlString) {
                        AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                            placeholder: { Color.orange.opacity(0.1) }
                            .frame(width: 56, height: 56).cornerRadius(8).clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1))
                            .frame(width: 56, height: 56)
                            .overlay(Image(systemName: "fork.knife").foregroundColor(.orange.opacity(0.6)))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.menuItem.name).font(.subheadline).fontWeight(.semibold)
                        if !item.optionSummary.isEmpty {
                            Text(item.optionSummary).font(.caption).foregroundColor(.secondary).lineLimit(2)
                        }
                        Text("₺\(String(format: "%.2f", item.pricePerUnit)) / adet")
                            .font(.caption).foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text("₺\(String(format: "%.2f", item.lineTotal))")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(.orange)

                        HStack(spacing: 0) {
                            // Minus / trash button
                            Button {
                                if item.quantity <= 1 {
                                    cart.removeItem(cartItemId)
                                } else {
                                    cart.updateQuantity(cartItemId, delta: -1)
                                }
                            } label: {
                                Image(systemName: item.quantity <= 1 ? "trash" : "minus")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(item.quantity <= 1 ? .red : .orange)
                                    .frame(width: 30, height: 30)
                                    .background((item.quantity <= 1 ? Color.red : Color.orange).opacity(0.12))
                                    .clipShape(Circle())
                            }

                            Text("\(item.quantity)")
                                .font(.subheadline).fontWeight(.semibold)
                                .frame(minWidth: 28)
                                .multilineTextAlignment(.center)

                            // Plus button
                            Button {
                                cart.updateQuantity(cartItemId, delta: 1)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Color.orange)
                                    .clipShape(Circle())
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }
}
