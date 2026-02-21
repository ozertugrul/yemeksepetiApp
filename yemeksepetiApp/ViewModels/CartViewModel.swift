import Foundation
import Combine

// MARK: - CartItem

struct CartItem: Identifiable {
    var id: String = UUID().uuidString
    var menuItem: MenuItem
    var quantity: Int
    var selectedOptionGroups: [SelectedOptionGroup]
    var optionExtrasPerUnit: Double

    var pricePerUnit: Double { menuItem.discountedPrice + optionExtrasPerUnit }
    var lineTotal: Double { pricePerUnit * Double(quantity) }

    var optionSummary: String {
        let opts = selectedOptionGroups.flatMap { $0.selectedOptions }
        return opts.isEmpty ? "" : opts.joined(separator: ", ")
    }
}

// MARK: - CartViewModel

final class CartViewModel: ObservableObject {
    @Published var items: [CartItem] = []
    @Published var restaurantId: String?
    @Published var restaurantName: String?
    @Published var restaurant: Restaurant?

    // ── Computed ────────────────────────────────────────────────────────

    var isEmpty: Bool { items.isEmpty }
    var itemCount: Int { items.reduce(0) { $0 + $1.quantity } }
    var subtotal: Double { items.reduce(0) { $0 + $1.lineTotal } }
    var deliveryFee: Double { 0 }   // Ücretsiz teslimat — ileride dinamik yapılabilir
    var total: Double { subtotal + deliveryFee }

    // ── Add Item ─────────────────────────────────────────────────────────

    /// Adds an item to the cart. If items are from a different restaurant, clears first.
    func addItem(
        _ menuItem: MenuItem,
        quantity: Int = 1,
        selectedOptionGroups: [SelectedOptionGroup] = [],
        optionExtrasPerUnit: Double = 0,
        restaurantId: String,
        restaurantName: String,
        restaurant: Restaurant? = nil
    ) {
        // If cart contains items from a different restaurant, clear first
        if let currentRestaurantId = self.restaurantId, currentRestaurantId != restaurantId {
            clear()
        }

        self.restaurantId = restaurantId
        self.restaurantName = restaurantName
        if let restaurant = restaurant { self.restaurant = restaurant }

        // Try to merge with existing identical item (same options)
        let optionKey = selectedOptionGroups.flatMap { $0.selectedOptions }.sorted().joined()
        if let idx = items.firstIndex(where: {
            $0.menuItem.id == menuItem.id &&
            $0.selectedOptionGroups.flatMap { $0.selectedOptions }.sorted().joined() == optionKey
        }) {
            items[idx].quantity += quantity
        } else {
            let newItem = CartItem(
                menuItem: menuItem,
                quantity: quantity,
                selectedOptionGroups: selectedOptionGroups,
                optionExtrasPerUnit: optionExtrasPerUnit
            )
            items.append(newItem)
        }
    }

    // ── Remove Item ──────────────────────────────────────────────────────

    func removeItem(_ id: String) {
        items.removeAll { $0.id == id }
        if items.isEmpty { clear() }
    }

    // ── Update Quantity ──────────────────────────────────────────────────

    func updateQuantity(_ id: String, delta: Int) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let newQty = items[idx].quantity + delta
        if newQty <= 0 {
            items.remove(at: idx)
            if items.isEmpty { clear() }
        } else {
            items[idx].quantity = newQty
        }
    }

    // ── Clear ────────────────────────────────────────────────────────────

    func clear() {
        items = []
        restaurantId = nil
        restaurantName = nil
        restaurant = nil
    }

    // ── Build Order ──────────────────────────────────────────────────────

    func buildOrder(
        userId: String,
        userEmail: String,
        deliveryAddress: UserAddress?,
        paymentMethod: PaymentMethod,
        note: String?,
        appliedCoupons: [AppliedCoupon] = [],
        discountAmount: Double = 0
    ) -> Order {
        let orderItems = items.map { cartItem in
            OrderItem(
                menuItemId: cartItem.menuItem.id,
                name: cartItem.menuItem.name,
                unitPrice: cartItem.menuItem.discountedPrice,
                quantity: cartItem.quantity,
                selectedOptionGroups: cartItem.selectedOptionGroups,
                optionExtrasPerUnit: cartItem.optionExtrasPerUnit,
                imageUrl: cartItem.menuItem.imageUrl
            )
        }

        let pickupCode: String? = (paymentMethod == .pickup) ? generatePickupCode() : nil
        let finalTotal = max(0, total - discountAmount)

        return Order(
            restaurantId: restaurantId ?? "",
            restaurantName: restaurantName ?? "",
            userId: userId,
            userEmail: userEmail,
            items: orderItems,
            subtotal: subtotal,
            deliveryFee: deliveryFee,
            total: finalTotal,
            paymentMethod: paymentMethod,
            deliveryAddress: deliveryAddress,
            pickupCode: pickupCode,
            note: (note?.trimmingCharacters(in: .whitespaces).isEmpty == false) ? note : nil,
            appliedCoupons: appliedCoupons,
            discountAmount: discountAmount
        )
    }

    private func generatePickupCode() -> String {
        String(format: "%04d", Int.random(in: 1000...9999))
    }
}
