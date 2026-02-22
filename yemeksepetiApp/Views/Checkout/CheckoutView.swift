import SwiftUI
import MapKit
import CoreLocation

// MARK: - CheckoutView

struct CheckoutView: View {
    @ObservedObject var cart: CartViewModel
    @ObservedObject var viewModel: AppViewModel
    var onSuccess: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var addresses: [UserAddress] = []
    @State private var savedCards: [SavedCard] = []
    @State private var selectedAddress: UserAddress?
    @State private var selectedCard: SavedCard?
    @State private var selectedPayment: PaymentMethod = .cashOnDelivery
    @State private var orderNote: String = ""
    @State private var isLoading = false
    @State private var isPlacingOrder = false
    @State private var placedOrder: Order?
    @State private var errorMessage: String?
    @State private var showingAddressSheet = false
    @State private var orderCompletedSuccessfully = false
    // Kupon — aynı anda yalnızca 1 kupon aktif edilebilir
    @State private var appliedCoupon: AppliedCoupon? = nil
    @State private var availableCoupons: [Coupon] = []
    @State private var couponCodeInput: String = ""
    @State private var couponError: String? = nil
    @State private var isValidatingCoupon = false

    private var appliedDiscountTotal: Double { appliedCoupon?.discountAmount ?? 0 }
    private var finalTotal: Double { max(0, cart.total - appliedDiscountTotal) }

    private var restaurant: Restaurant? { cart.restaurant }
    private var allowsPickup: Bool { restaurant?.allowsPickup ?? false }
    private var allowsCashOnDelivery: Bool { restaurant?.allowsCashOnDelivery ?? false }

    private var currentUser: AppUser? { viewModel.authService.currentUser }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // ── 1. Teslimat Adresi ──────────────────────────────
                    addressSection

                    // ── 2. Sipariş Özeti ────────────────────────────────
                    orderSummarySection

                    // ── 3. Kupon ──────────────────────────────────────────
                    couponSection

                    // ── 4. Ödeme Yöntemi ─────────────────────────────────
                    paymentSection

                    // ── 5. Sipariş Notu ──────────────────────────────────
                    noteSection

                    if let error = errorMessage {
                        Text(error).font(.caption).foregroundColor(.red).padding(.horizontal)
                    }

                    // ── 5. Onayla ───────────────────────────────────────
                    confirmButton
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("Sipariş Özeti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
            }
            .onAppear { loadData() }
        }
        .fullScreenCover(item: $placedOrder, onDismiss: {
            if orderCompletedSuccessfully {
                orderCompletedSuccessfully = false
                dismiss()       // close CheckoutView sheet
                onSuccess()     // switch to home tab
            }
        }) { order in
            OrderConfirmationView(order: order, cart: cart, onComplete: {
                orderCompletedSuccessfully = true
                placedOrder = nil
            })
        }
    }

    // ── Address Section ───────────────────────────────────────────────────

    private var addressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Teslimat Adresi", icon: "mappin.and.ellipse")

            if addresses.isEmpty {
                Text("Kayıtlı adres yok. Lütfen adres ekleyin.")
                    .font(.caption).foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    ForEach(addresses) { address in
                        AddressSelectionRow(
                            address: address,
                            isSelected: selectedAddress?.id == address.id
                        ) {
                            selectedAddress = address
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Map preview — .id forces full recreation when address changes
            if let addr = selectedAddress {
                AddressMapPreview(address: addr)
                    .id(addr.id)
                    .padding(.horizontal)
            }

            Button {
                showingAddressSheet = true
            } label: {
                Label(addresses.isEmpty ? "Adres Ekle" : "Adresleri Yönet", systemImage: "plus.circle")
                    .font(.caption).foregroundColor(.orange)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .padding(.horizontal)
        .sheet(isPresented: $showingAddressSheet) {
            if let uid = currentUser?.id {
                UserAddressesView(viewModel: viewModel)
                    .onDisappear { loadAddresses(uid: uid) }
            }
        }
    }

    // ── Order Summary Section ─────────────────────────────────────────────

    private var orderSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Sipariş Detayları", icon: "list.bullet.rectangle")

            VStack(spacing: 0) {
                ForEach(cart.items) { cartItem in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("\(cartItem.quantity)x").font(.subheadline).fontWeight(.bold)
                                    .foregroundColor(.orange)
                                Text(cartItem.menuItem.name).font(.subheadline)
                            }
                            if !cartItem.optionSummary.isEmpty {
                                Text(cartItem.optionSummary).font(.caption)
                                    .foregroundColor(.secondary).padding(.leading, 4)
                            }
                        }
                        Spacer()
                        Text("₺\(String(format: "%.2f", cartItem.lineTotal))")
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    .padding(.vertical, 6)
                    if cartItem.id != cart.items.last?.id { Divider() }
                }
            }
            .padding(.horizontal)

            Divider().padding(.horizontal)

            VStack(spacing: 6) {
                CheckoutRow(label: "Ara Toplam", value: "₺\(String(format: "%.2f", cart.subtotal))")
                CheckoutRow(label: "Teslimat Ücreti",
                            value: cart.deliveryFee > 0 ? "₺\(String(format: "%.2f", cart.deliveryFee))" : "Ücretsiz",
                            valueColor: .green)
                if appliedDiscountTotal > 0 {
                    CheckoutRow(label: "Kupon İndirimi",
                                value: "-₺\(String(format: "%.2f", appliedDiscountTotal))",
                                valueColor: .green)
                }
                Divider()
                CheckoutRow(label: "Toplam", value: "₺\(String(format: "%.2f", finalTotal))",
                            labelWeight: .bold, valueColor: .orange)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .padding(.horizontal)
    }

    // ── Payment Section ───────────────────────────────────────────────────

    private var paymentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Ödeme Yöntemi", icon: "creditcard")

            VStack(spacing: 8) {
                // Online Card (disabled)
                PaymentOptionRow(
                    icon: "creditcard.fill",
                    title: "Online Kart",
                    subtitle: "Yakında çalışacak",
                    isSelected: false,
                    isDisabled: true
                ) {}

                // Cash on Delivery
                if allowsCashOnDelivery {
                    PaymentOptionRow(
                        icon: "banknote",
                        title: "Kapıda Nakit",
                        subtitle: nil,
                        isSelected: selectedPayment == .cashOnDelivery,
                        isDisabled: false
                    ) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            selectedPayment = .cashOnDelivery
                        }
                    }

                    PaymentOptionRow(
                        icon: "creditcard",
                        title: "Kapıda Kart",
                        subtitle: "Kredi / Banka Kartı",
                        isSelected: selectedPayment == .cardOnDelivery,
                        isDisabled: false
                    ) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            selectedPayment = .cardOnDelivery
                        }
                    }
                }

                // Pickup
                if allowsPickup {
                    PaymentOptionRow(
                        icon: "figure.walk",
                        title: "Gel & Al",
                        subtitle: nil,
                        isSelected: selectedPayment == .pickup,
                        isDisabled: false
                    ) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            selectedPayment = .pickup
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .padding(.horizontal)
        .onAppear { setDefaultPayment() }
    }

    // ── Coupon Section ───────────────────────────────────────────────

    private var couponSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Kupon Kodu", icon: "ticket.fill")

            // Kupon kodu giriş alanı
            HStack(spacing: 8) {
                TextField("Kupon kodunu girin...", text: $couponCodeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                Button {
                    applyCode()
                } label: {
                    if isValidatingCoupon {
                        ProgressView().frame(width: 70, height: 36)
                    } else {
                        Text("Uygula")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 70, height: 36)
                            .background(couponCodeInput.isEmpty ? Color.gray : Color.orange)
                            .cornerRadius(10)
                    }
                }
                .buttonStyle(.plain)
                .disabled(couponCodeInput.isEmpty || isValidatingCoupon)
            }
            .padding(.horizontal)

            // Hata mesajı
            if let err = couponError {
                Text(err).font(.caption).foregroundColor(.red).padding(.horizontal)
            }

            // Aynı anda yalnızca 1 kupon uyarısı
            if appliedCoupon != nil {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").font(.caption).foregroundColor(.secondary)
                    Text("Aynı anda yalnızca 1 kupon aktif edilebilir.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }

            // Kullanılabilir public kuponlar (hızlı seçim)
            if !availableCoupons.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableCoupons) { coupon in
                            let isApplied = appliedCoupon?.couponId == coupon.id
                            Button {
                                if isApplied {
                                    appliedCoupon = nil
                                } else {
                                    couponCodeInput = coupon.code
                                    applyCode()
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(coupon.code)
                                        .font(.system(.caption, design: .monospaced)).fontWeight(.bold)
                                    Text(coupon.discountLabel).font(.caption2)
                                }
                                .foregroundColor(isApplied ? .white : .orange)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(isApplied ? Color.orange : Color.orange.opacity(0.1))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // Uygulanmış kupon
            if let ac = appliedCoupon {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text(ac.code)
                        .font(.system(.subheadline, design: .monospaced)).fontWeight(.semibold)
                    Spacer()
                    Text("-₺\(String(format: "%.2f", ac.discountAmount))")
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(.green)
                    Button { appliedCoupon = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.green.opacity(0.06))
                .cornerRadius(8)
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .padding(.horizontal)
    }

    // ── Note Section ──────────────────────────────────────────────────────

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Sipariş Notu", icon: "note.text")
            ZStack(alignment: .topLeading) {
                if orderNote.isEmpty {
                    Text("Örn: Zili çalmayın, kapıya bırakın...")
                        .foregroundColor(Color(.placeholderText))
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $orderNote)
                    .frame(minHeight: 75, maxHeight: 100)
            }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .padding(.horizontal)
    }

    // ── Confirm Button ────────────────────────────────────────────────────

    private var confirmButton: some View {
        Button {
            placeOrder()
        } label: {
            HStack {
                if isPlacingOrder {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Siparişi Tamamla")
                    Spacer()
                    Text("₺\(String(format: "%.2f", finalTotal))").fontWeight(.bold)
                }
            }
            .font(.headline).foregroundColor(.white)
            .padding()
            .background(canPlaceOrder ? Color.orange : Color.gray)
            .cornerRadius(14)
        }
        .disabled(!canPlaceOrder || isPlacingOrder)
        .padding(.horizontal)
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private var canPlaceOrder: Bool {
        guard selectedAddress != nil else { return false }
        // Seçili ödeme yönteminin restoran tarafından desteklendiğini doğrula
        switch selectedPayment {
        case .cashOnDelivery, .cardOnDelivery: return allowsCashOnDelivery
        case .pickup:                          return allowsPickup
        case .onlineCard:                      return false  // Henüz aktif değil
        }
    }

    private func loadData() {
        guard let uid = currentUser?.id else { return }
        isLoading = true
        loadAddresses(uid: uid)
        viewModel.dataService.fetchCards(uid: uid) { cards in
            self.savedCards = cards
            self.selectedCard = cards.first(where: { $0.isDefault }) ?? cards.first
            self.isLoading = false
        }
        // Kullanıcının şehrine göre geçerli kuponları öncüden yükle
        let city = viewModel.authService.currentUser?.city
        viewModel.couponService.fetchApplicableCoupons(
            restaurantId: cart.restaurantId ?? "",
            cartTotal: cart.total,
            city: city?.isEmpty == false ? city : nil
        ) { fetched in
            self.availableCoupons = fetched
        }
    }

    private func loadAddresses(uid: String) {
        viewModel.dataService.fetchAddresses(uid: uid) { addrs in
            self.addresses = addrs
            if self.selectedAddress == nil || !addrs.contains(where: { $0.id == self.selectedAddress?.id }) {
                self.selectedAddress = addrs.first(where: { $0.isDefault }) ?? addrs.first
            }
        }
    }

    private func setDefaultPayment() {
        if allowsCashOnDelivery {
            selectedPayment = .cashOnDelivery
        } else if allowsPickup {
            selectedPayment = .pickup
        }
    }

    private func placeOrder() {
        guard let user = currentUser else { errorMessage = "Giriş yapmanız gerekiyor."; return }
        if selectedAddress == nil {
            errorMessage = "Lütfen bir teslimat adresi seçin."
            return
        }

        isPlacingOrder = true
        errorMessage = nil

        let order = cart.buildOrder(
            userId: user.id,
            userEmail: user.email,
            deliveryAddress: selectedAddress,
            paymentMethod: selectedPayment,
            note: orderNote.isEmpty ? nil : orderNote,
            appliedCoupons: appliedCoupon.map { [$0] } ?? [],
            discountAmount: appliedDiscountTotal
        )

        viewModel.orderService.placeOrder(order) { result in
            isPlacingOrder = false
            switch result {
            case .success(let placed):
                // Kupon kullanım sayısını güncelle
                if let ac = self.appliedCoupon {
                    self.viewModel.couponService.recordUsages(
                        couponIds: [ac.couponId],
                        userId: user.id
                    )
                }
                placedOrder = placed
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    // ── Coupon Helpers ────────────────────────────────────────────────

    private func applyCode() {
        guard let user = currentUser else { return }
        let code = couponCodeInput.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        isValidatingCoupon = true
        couponError = nil
        // Zaten aktif bir kupon varsa önce kaldır, yeni kuponu uygula
        viewModel.couponService.validateCoupon(
            code: code,
            restaurantId: cart.restaurantId,
            cartTotal: cart.total,
            userId: user.id,
            alreadyAppliedIds: []
        ) { result in
            isValidatingCoupon = false
            switch result {
            case .success(let coupon):
                let discount = coupon.calculatedDiscount(for: finalTotal)
                appliedCoupon = AppliedCoupon(couponId: coupon.id, code: coupon.code, discountAmount: discount)
                couponCodeInput = ""
            case .failure(let error):
                couponError = error.localizedDescription
            }
        }
    }

    private func removeCoupon(_ couponId: String) {
        if appliedCoupon?.couponId == couponId { appliedCoupon = nil }
    }
}

// MARK: - AddressMapPreview

struct AddressMapPreview: View {
    let address: UserAddress
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.015, longitude: 28.979),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var coordinate: CLLocationCoordinate2D?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Compact address text
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill").foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(address.title).font(.caption).fontWeight(.semibold)
                    Text(address.fullAddress).font(.caption).foregroundColor(.secondary).lineLimit(2)
                }
                Spacer()
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            // Map
            Map(coordinateRegion: $region, annotationItems: coordinate.map { [MapPin(coordinate: $0)] } ?? []) { pin in
                MapMarker(coordinate: pin.coordinate, tint: .red)
            }
            .frame(height: 140)
            .cornerRadius(10)
            .disabled(true)
            .overlay {
                if coordinate == nil {
                    ZStack {
                        Color(.systemGray5).cornerRadius(10)
                        ProgressView()
                    }
                }
            }
        }
        .onAppear { load() }
        .onChange(of: address.id) { _ in load() }
    }

    private func load() {
        // If coordinates were saved with the address, use them instantly.
        if let lat = address.latitude, let lon = address.longitude {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            coordinate = coord
            region = MKCoordinateRegion(center: coord,
                                        span: MKCoordinateSpan(latitudeDelta: 0.005,
                                                               longitudeDelta: 0.005))
        } else {
            // Fall back to geocoding the address string
            geocode()
        }
    }

    private func geocode() {
        coordinate = nil
        CLGeocoder().geocodeAddressString(address.fullAddress,
                                          in: nil,
                                          preferredLocale: Locale(identifier: "tr_TR")) { placemarks, _ in
            DispatchQueue.main.async {
                if let loc = placemarks?.first?.location?.coordinate {
                    coordinate = loc
                    region = MKCoordinateRegion(center: loc,
                                               span: MKCoordinateSpan(latitudeDelta: 0.005,
                                                                      longitudeDelta: 0.005))
                }
            }
        }
    }
}

private struct MapPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Helper Views

private struct SectionHeader: View {
    let title: String; let icon: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(.orange)
            Text(title).font(.headline)
        }
        .padding(.horizontal)
    }
}

private struct CheckoutRow: View {
    let label: String; let value: String
    var labelWeight: Font.Weight = .regular
    var valueColor: Color = .primary
    var body: some View {
        HStack {
            Text(label).font(.subheadline).fontWeight(labelWeight)
            Spacer()
            Text(value).font(.subheadline).fontWeight(labelWeight).foregroundColor(valueColor)
        }
    }
}

private struct AddressSelectionRow: View {
    let address: UserAddress
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(isSelected ? Color.orange : Color(.systemGray4), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected { Circle().fill(Color.orange).frame(width: 12, height: 12) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(address.title).font(.subheadline).fontWeight(.semibold)
                        if address.isDefault {
                            Text("Varsayılan").font(.caption2).foregroundColor(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.green).cornerRadius(4)
                        }
                    }
                    Text(address.fullAddress).font(.caption).foregroundColor(.secondary).lineLimit(2)
                    if !address.phone.isEmpty {
                        Label(address.phone, systemImage: "phone")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(isSelected ? Color.orange.opacity(0.06) : Color(.systemGray6))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

private struct PaymentOptionRow: View {
    let icon: String; let title: String; let subtitle: String?
    let isSelected: Bool; let isDisabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3)
                    .foregroundColor(isDisabled ? .gray : (isSelected ? .orange : .primary))
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.subheadline).fontWeight(isSelected ? .semibold : .regular)
                            .foregroundColor(isDisabled ? .gray : .primary)
                        if isDisabled {
                            Text("Yakında").font(.caption2).foregroundColor(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.gray).cornerRadius(4)
                        }
                    }
                    if let sub = subtitle {
                        Text(sub).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.orange)
                }
            }
            .padding(12)
            .background(isSelected ? Color.orange.opacity(0.08) : Color(.systemGray6))
            .cornerRadius(10)
            .opacity(isDisabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
