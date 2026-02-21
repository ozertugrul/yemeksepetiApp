import SwiftUI

// MARK: - SuggestedItemsSheet

/// "Yanında iyi gider" önerileri — Sepete eft ürün eklendikten sonra gösterilir
struct SuggestedItemsSheet: View {
    let restaurant: Restaurant
    let addedItemName: String
    @ObservedObject var cart: CartViewModel
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingOptionSheetFor: MenuItem?

    private var suggestedItems: [MenuItem] {
        // Find suggested ids from cart items' menu
        let suggestedIds = cart.items
            .flatMap { cartItem in
                restaurant.menu.first(where: { $0.id == cartItem.menuItem.id })?.suggestedItemIds ?? []
            }
        let uniqueIds = Array(Set(suggestedIds))
        return uniqueIds.compactMap { id in
            restaurant.menu.first(where: { $0.id == id && $0.isAvailable })
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 6) {
                    Image(systemName: "bag.badge.plus").font(.largeTitle).foregroundColor(.orange)
                    Text("\(addedItemName) sepete eklendi!")
                        .font(.headline)
                    Text("Bunları da almak ister misin?")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .padding(.top, 10).padding(.bottom, 16)

                Divider()

                if suggestedItems.isEmpty {
                    Spacer()
                    Text("Öneri bulunamadı").foregroundColor(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(suggestedItems) { item in
                                SuggestedItemRow(item: item) {
                                    if item.optionGroups.isEmpty {
                                        // Direkt ekle
                                        cart.addItem(
                                            item,
                                            quantity: 1,
                                            restaurantId: restaurant.id,
                                            restaurantName: restaurant.name,
                                            restaurant: restaurant
                                        )
                                    } else {
                                        showingOptionSheetFor = item
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }

                Divider()
                Button {
                    onDismiss()
                    dismiss()
                } label: {
                    Text("Geç, devam et")
                        .font(.subheadline).foregroundColor(.secondary)
                        .padding(.vertical, 12)
                }
            }
            .navigationTitle("Yanında iyi gider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { onDismiss(); dismiss() }) {
                        Text("Sepete Git").fontWeight(.semibold).foregroundColor(.orange)
                    }
                }
            }
        }
        .sheet(item: $showingOptionSheetFor) { item in
            ItemOptionSheet(item: item, restaurant: restaurant, cart: cart) {
                onDismiss()
                dismiss()
            }
        }
    }
}

// MARK: - SuggestedItemRow

private struct SuggestedItemRow: View {
    let item: MenuItem
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let urlString = item.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { Color.orange.opacity(0.1) }
                    .frame(width: 64, height: 64).cornerRadius(10).clipped()
            } else {
                RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1))
                    .frame(width: 64, height: 64)
                    .overlay(Image(systemName: "fork.knife").foregroundColor(.orange))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.subheadline).fontWeight(.semibold)
                if !item.description.isEmpty {
                    Text(item.description).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Text("₺\(String(format: "%.2f", item.discountedPrice))")
                    .font(.subheadline).fontWeight(.bold).foregroundColor(.orange)
            }

            Spacer()

            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2).foregroundColor(.orange)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}
