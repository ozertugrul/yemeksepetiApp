import SwiftUI

// MARK: - HomeView

struct HomeView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var allRestaurants: [Restaurant] = []
    @State private var isLoading = false
    @State private var searchQuery = ""
    @State private var showingAddressPicker = false
    @State private var showingAddAddress = false
    @State private var savedAddresses: [UserAddress] = []
    @State private var selectedAddress: UserAddress?
    // fallback: city picked without an address (onboarding path)
    @State private var showingCityPicker = false
    @State private var pickerCity = ""
    @State private var manualCity: String = ""

    private var selectedCity: String? {
        if let city = selectedAddress?.city, !city.isEmpty { return city }
        if !manualCity.isEmpty { return manualCity }
        let city = viewModel.authService.currentUser?.city
        return (city?.isEmpty == false) ? city : nil
    }

    private var needsCityOnboarding: Bool {
        viewModel.authService.isAuthenticated && selectedCity == nil
    }

    private var filteredRestaurants: [Restaurant] {
        var result = allRestaurants
        if let city = selectedCity {
            result = result.filter { ($0.city ?? "").isEmpty || $0.city == city }
        }
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            result = result.filter {
                $0.name.lowercased().contains(q) || $0.cuisineType.lowercased().contains(q)
            }
        }
        return result
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !needsCityOnboarding {
                    // ── Address bar ──────────────────────────────────────
                    addressBar
                        .padding(.horizontal)
                        .padding(.top, 6)
                        .padding(.bottom, 8)

                    // ── Search bar ───────────────────────────────────────
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundColor(.gray)
                        TextField("Restoran veya mutfak ara...", text: $searchQuery)
                            .textInputAutocapitalization(.never)
                        if !searchQuery.isEmpty {
                            Button { searchQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                    Divider()
                }

                // ── Content ──────────────────────────────────────────────
                if needsCityOnboarding {
                    cityOnboardingView
                } else if isLoading {
                    Spacer()
                    ProgressView("Mağazalar yükleniyor...")
                    Spacer()
                } else if filteredRestaurants.isEmpty {
                    Spacer()
                    VStack(spacing: 14) {
                        Image(systemName: "storefront")
                            .font(.system(size: 52)).foregroundColor(.orange.opacity(0.6))
                        if let city = selectedCity {
                            Text("\(city)'de mağaza bulunamadı").font(.headline)
                            Text("Bu şehirde henüz hizmet verilmiyor olabilir.")
                                .font(.subheadline).foregroundColor(.secondary)
                            Button("Adresi Değiştir") { showingAddressPicker = true }
                                .buttonStyle(.borderedProminent).tint(.orange)
                        } else {
                            Text("Restoran bulunamadı").foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredRestaurants) { restaurant in
                                NavigationLink(destination: RestaurantDetailView(restaurant: restaurant, viewModel: viewModel)) {
                                    RestaurantCard(restaurant: restaurant)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .refreshable { loadRestaurants() }
                }
            }
            .navigationTitle("Yemeksepeti")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadRestaurants()
                refreshAddresses()
            }
            .onReceive(viewModel.authService.$user) { user in
                guard let uid = user?.id else {
                    savedAddresses = []; selectedAddress = nil; return
                }
                refreshAddresses(uid: uid)
            }
            .sheet(isPresented: $showingAddressPicker) {
                AddressPickerSheet(
                    addresses: $savedAddresses,
                    selectedAddress: $selectedAddress,
                    onAddNew: {
                        showingAddressPicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showingAddAddress = true
                        }
                    }
                )
            }
            .sheet(isPresented: $showingAddAddress, onDismiss: { refreshAddresses() }) {
                AddAddressView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingCityPicker, onDismiss: {
                if !pickerCity.isEmpty { manualCity = pickerCity; saveManualCity(pickerCity) }
            }) {
                CityPickerSheet(selectedCity: $pickerCity)
            }
        }
    }

    // MARK: - Address Bar

    private var addressBar: some View {
        Button { showingAddressPicker = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 1) {
                    Text(selectedAddress != nil ? selectedAddress!.title : "Adres Seç")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(addressBarSubtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    private var addressBarSubtitle: String {
        if let addr = selectedAddress {
            let parts = [addr.neighborhood, addr.district, addr.city]
                .filter { !$0.isEmpty }
            return parts.prefix(2).joined(separator: ", ")
        }
        if let city = selectedCity { return city }
        return "Konumunuzu belirleyin"
    }

    // MARK: - City Onboarding View

    private var cityOnboardingView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.orange)

                VStack(spacing: 8) {
                    Text("Konumunuzu Belirleyin")
                        .font(.title2).fontWeight(.bold)
                    Text("Size en yakın restoranları listeleyebilmemiz için bulunduğunuz ili seçin veya adresinizi ekleyin.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(spacing: 12) {
                    Button {
                        showingAddAddress = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Adres Ekle").fontWeight(.semibold)
                        }
                        .font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.orange).cornerRadius(14)
                    }

                    Button {
                        pickerCity = ""
                        showingCityPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                            Text("Sadece İl Seç").fontWeight(.semibold)
                        }
                        .font(.headline).foregroundColor(.orange)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.orange.opacity(0.1)).cornerRadius(14)
                    }
                }
                .padding(.horizontal, 32)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Helpers

    private func loadRestaurants() {
        isLoading = true
        viewModel.dataService.fetchRestaurants { fetched in
            allRestaurants = fetched
            isLoading = false
        }
    }

    private func refreshAddresses(uid: String? = nil) {
        let resolvedUid = uid ?? viewModel.authService.currentUser?.id
        guard let resolvedUid else { return }
        viewModel.dataService.fetchAddresses(uid: resolvedUid) { addresses in
            savedAddresses = addresses
            // Keep current selection if still valid; otherwise pick default/first
            if let current = selectedAddress, addresses.contains(where: { $0.id == current.id }) {
                // re-assign to get fresh data
                selectedAddress = addresses.first(where: { $0.id == current.id })
            } else {
                selectedAddress = addresses.first(where: { $0.isDefault }) ?? addresses.first
            }
        }
    }

    private func saveManualCity(_ city: String) {
        guard !city.isEmpty, let uid = viewModel.authService.currentUser?.id else { return }
        viewModel.dataService.updateUserProfile(uid: uid, data: ["city": city]) { _ in
            viewModel.authService.refreshCurrentUser()
        }
    }
}

// MARK: - AddressPickerSheet

private struct AddressPickerSheet: View {
    @Binding var addresses: [UserAddress]
    @Binding var selectedAddress: UserAddress?
    let onAddNew: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if addresses.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "mappin.slash.circle")
                            .font(.system(size: 56)).foregroundColor(.orange.opacity(0.5))
                        Text("Kayıtlı adres yok")
                            .font(.headline)
                        Text("Teslimat adresi ekleyerek başlayın.")
                            .font(.subheadline).foregroundColor(.secondary)
                        Button {
                            onAddNew()
                        } label: {
                            Label("Adres Ekle", systemImage: "plus.circle.fill")
                                .font(.headline).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding()
                                .background(Color.orange).cornerRadius(14)
                        }
                        .padding(.horizontal, 32)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(addresses) { address in
                            Button {
                                selectedAddress = address
                                dismiss()
                            } label: {
                                HStack(spacing: 14) {
                                    // Icon
                                    ZStack {
                                        Circle()
                                            .fill(selectedAddress?.id == address.id
                                                  ? Color.orange : Color(.systemGray5))
                                            .frame(width: 38, height: 38)
                                        Image(systemName: addressIcon(for: address.title))
                                            .font(.system(size: 16))
                                            .foregroundColor(selectedAddress?.id == address.id
                                                             ? .white : .secondary)
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(address.title)
                                                .font(.subheadline.weight(.semibold))
                                            if address.isDefault {
                                                Text("Varsayılan")
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                                    .background(Color.green).cornerRadius(5)
                                            }
                                        }
                                        Text([address.neighborhood, address.district, address.city]
                                            .filter { !$0.isEmpty }.joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                        if !address.street.isEmpty {
                                            Text(address.street +
                                                 (address.buildingNo.isEmpty ? "" : " No:\(address.buildingNo)") +
                                                 (address.flatNo.isEmpty ? "" : "/\(address.flatNo)"))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    if selectedAddress?.id == address.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.orange)
                                            .font(.title3)
                                    }
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        // Add new row
                        Button {
                            onAddNew()
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle().fill(Color.orange.opacity(0.12))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.orange)
                                }
                                Text("Yeni Adres Ekle")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.orange)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Teslimat Adresi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    private func addressIcon(for title: String) -> String {
        switch title.lowercased() {
        case let t where t.contains("ev"):    return "house.fill"
        case let t where t.contains("iş"):   return "briefcase.fill"
        case let t where t.contains("okul"): return "graduationcap.fill"
        default: return "mappin.fill"
        }
    }
}

// MARK: - RestaurantCard

struct RestaurantCard: View {
    let restaurant: Restaurant

    private var displayRating: Double {
        restaurant.ratingCount > 0 ? restaurant.averageRating : restaurant.rating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Hero image ──────────────────────────────────────────────
            ZStack(alignment: .topTrailing) {
                Group {
                    if let urlStr = restaurant.imageUrl, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            case .empty, .failure:
                                imagePlaceholder
                            @unknown default:
                                imagePlaceholder
                            }
                        }
                    } else {
                        imagePlaceholder
                    }
                }
                .frame(height: 148)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.18)],
                        startPoint: .center, endPoint: .bottom
                    )
                )

                // Closed / Open badge
                if !restaurant.isActive {
                    Text("Kapalı")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                        .padding(8)
                }
            }

            // ── Info section ────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {

                // Name
                Text(restaurant.name)
                    .font(.headline)
                    .lineLimit(1)

                // Cuisine
                Text(restaurant.cuisineType)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                // Stats row
                HStack(spacing: 0) {
                    // Rating
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text(String(format: "%.1f", displayRating))
                            .font(.caption.weight(.semibold))
                        if restaurant.ratingCount > 0 {
                            Text("(\(restaurant.ratingCount))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Delivery time
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(restaurant.deliveryTime)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if restaurant.minOrderAmount > 0 {
                        Spacer()
                        // Min order
                        HStack(spacing: 4) {
                            Image(systemName: "bag")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("Min ₺\(Int(restaurant.minOrderAmount))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Successful orders chip
                if restaurant.successfulOrderCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                        Text("\(restaurant.successfulOrderCount)+ başarılı sipariş")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
        .opacity(restaurant.isActive ? 1 : 0.70)
    }

    private var imagePlaceholder: some View {
        Color.orange.opacity(0.10)
            .overlay(
                Image(systemName: "storefront")
                    .font(.system(size: 44))
                    .foregroundColor(.orange.opacity(0.35))
            )
    }
}

// MARK: - RestaurantDetailView

struct RestaurantDetailView: View {
    let restaurant: Restaurant
    @ObservedObject var viewModel: AppViewModel

    @State private var showingOptionSheet: MenuItem?
    @State private var lastAddedItem: MenuItem?
    @State private var showingSuggested = false
    @State private var showingCart = false
    @State private var showingDifferentRestaurantAlert = false
    @State private var pendingItem: MenuItem?
    @State private var selectedCategory: String? = nil

    private var cart: CartViewModel { viewModel.cart }

    private var categories: [String] {
        Array(Set(restaurant.menu.filter(\.isAvailable).map(\.category))).sorted()
    }

    private var displayRating: Double {
        restaurant.ratingCount > 0 ? restaurant.averageRating : restaurant.rating
    }

    private func cartCount(for item: MenuItem) -> Int {
        guard cart.restaurantId == restaurant.id else { return 0 }
        return cart.items.filter { $0.menuItem.id == item.id }.reduce(0) { $0 + $1.quantity }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {

                        // ── Hero image ──────────────────────────────────────
                        heroHeader

                        // ── Quick stats strip ───────────────────────────────
                        statsStrip

                        // ── Description ─────────────────────────────────────
                        if !restaurant.description.isEmpty {
                            descriptionSection
                        }

                        // ── Feature badges ──────────────────────────────────
                        featureBadges

                        // ── Category tabs ────────────────────────────────────
                        if categories.count > 1 {
                            categoryTabs(proxy: proxy)
                        }

                        // ── Menu sections ────────────────────────────────────
                        ForEach(categories, id: \.self) { cat in
                            menuSection(category: cat)
                        }

                        Color.clear.frame(height: 100)
                    }
                }
            }

            // ── Floating cart bar ────────────────────────────────────────
            if !cart.isEmpty && cart.restaurantId == restaurant.id {
                cartBar
            }
        }
        .navigationTitle(restaurant.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $showingOptionSheet) { item in
            ItemOptionSheet(item: item, restaurant: restaurant, cart: cart) {
                lastAddedItem = item
                checkSuggestions(for: item)
            }
        }
        .sheet(isPresented: $showingSuggested) {
            if let added = lastAddedItem {
                SuggestedItemsSheet(restaurant: restaurant, addedItemName: added.name, cart: cart) {}
            }
        }
        .sheet(isPresented: $showingCart) {
            CartView(cart: cart, viewModel: viewModel)
        }
        .alert("Farklı Mağaza", isPresented: $showingDifferentRestaurantAlert) {
            Button("Sepeti Temizle ve Ekle", role: .destructive) {
                cart.clear()
                if let item = pendingItem { handleAddToCart(item: item) }
            }
            Button("İptal", role: .cancel) { pendingItem = nil }
        } message: {
            Text("Sepetinizde başka bir mağazadan ürün var. Devam ederseniz mevcut sepet temizlenecek.")
        }
    }

    // MARK: Hero

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let urlStr = restaurant.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            heroPlaceholder
                        }
                    }
                } else {
                    heroPlaceholder
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipped()

            // Bottom gradient
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .center, endPoint: .bottom
            )
            .frame(height: 220)

            // Name + cuisine + status badge
            VStack(alignment: .leading, spacing: 4) {
                if !restaurant.isActive {
                    Text("Şu an kapalı")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.red.opacity(0.85))
                        .cornerRadius(6)
                }
                Text(restaurant.name)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                Text(restaurant.cuisineType)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(16)
        }
    }

    private var heroPlaceholder: some View {
        Color.orange.opacity(0.10)
            .overlay(
                Image(systemName: "storefront")
                    .font(.system(size: 56))
                    .foregroundColor(.orange.opacity(0.3))
            )
    }

    // MARK: Stats Strip

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statCell(
                icon: "star.fill", iconColor: .orange,
                value: String(format: "%.1f", displayRating),
                label: restaurant.ratingCount > 0 ? "\(restaurant.ratingCount) puan" : "Yeni"
            )
            stripDivider
            statCell(
                icon: "clock", iconColor: .secondary,
                value: restaurant.deliveryTime,
                label: "Teslimat"
            )
            stripDivider
            statCell(
                icon: "bag", iconColor: .secondary,
                value: "₺\(Int(restaurant.minOrderAmount))",
                label: "Min. sipariş"
            )
            if restaurant.successfulOrderCount > 0 {
                stripDivider
                statCell(
                    icon: "checkmark.circle.fill", iconColor: .green,
                    value: "\(restaurant.successfulOrderCount)+",
                    label: "Sipariş"
                )
            }
        }
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private func statCell(icon: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundColor(iconColor).font(.system(size: 15))
            Text(value).font(.subheadline.weight(.bold))
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var stripDivider: some View {
        Rectangle().fill(Color(.systemGray4)).frame(width: 1, height: 36)
    }

    // MARK: Description

    private var descriptionSection: some View {
        HStack {
            Text(restaurant.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: Feature Badges

    @ViewBuilder
    private var featureBadges: some View {
        let badges = featureBadgeList
        if !badges.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(badges, id: \.label) { badge in
                        Label(badge.label, systemImage: badge.icon)
                            .font(.caption.weight(.medium))
                            .foregroundColor(badge.color)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(badge.color.opacity(0.1))
                            .cornerRadius(20)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color(.systemBackground))
            Divider()
        }
    }

    private struct FeatureBadge {
        let label: String; let icon: String; let color: Color
    }

    private var featureBadgeList: [FeatureBadge] {
        var list: [FeatureBadge] = []
        if restaurant.allowsPickup {
            list.append(.init(label: "Gel-Al", icon: "figure.walk", color: .blue))
        }
        if restaurant.allowsCashOnDelivery {
            list.append(.init(label: "Kapıda Ödeme", icon: "banknote", color: .green))
        }
        return list
    }

    // MARK: Category Tabs

    private func categoryTabs(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    let active = selectedCategory == cat
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            selectedCategory = cat
                            proxy.scrollTo("sec_\(cat)", anchor: .top)
                        }
                    } label: {
                        Text(cat)
                            .font(.caption.weight(active ? .bold : .medium))
                            .foregroundColor(active ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(active ? Color.orange : Color(.systemGray5))
                            .cornerRadius(20)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: Menu Section

    private func menuSection(category: String) -> some View {
        let items = restaurant.menu.filter { $0.category == category && $0.isAvailable }
        return VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text(category)
                .font(.headline.weight(.bold))
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 10)
                .id("sec_\(category)")
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGroupedBackground))

            // Item cards
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    MenuItemDetailRow(
                        item: item,
                        cartCount: cartCount(for: item),
                        onAdd: { handleAddToCart(item: item) }
                    )
                    if idx < items.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(.systemBackground))
        }
    }

    // MARK: Cart Bar

    private var cartBar: some View {
        Button { showingCart = true } label: {
            HStack(spacing: 12) {
                Text("\(cart.itemCount)")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.orange)
                    .frame(width: 30, height: 30)
                    .background(Color.white)
                    .cornerRadius(8)

                Text("Sepete Git")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Text("₺\(String(format: "%.2f", cart.total))")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.orange)
                    .shadow(color: .orange.opacity(0.45), radius: 10, y: 5)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: Helpers

    private func handleAddToCart(item: MenuItem) {
        if let cartRestId = cart.restaurantId, cartRestId != restaurant.id {
            pendingItem = item
            showingDifferentRestaurantAlert = true
            return
        }
        if item.optionGroups.isEmpty {
            cart.addItem(item, quantity: 1, restaurantId: restaurant.id,
                         restaurantName: restaurant.name, restaurant: restaurant)
            lastAddedItem = item
            checkSuggestions(for: item)
        } else {
            showingOptionSheet = item
        }
    }

    private func checkSuggestions(for item: MenuItem) {
        let ids = item.suggestedItemIds
        let available = ids.compactMap { id in
            restaurant.menu.first(where: { $0.id == id && $0.isAvailable })
        }
        if !available.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showingSuggested = true }
        }
    }
}

// MARK: - MenuItemDetailRow

private struct MenuItemDetailRow: View {
    let item: MenuItem
    let cartCount: Int
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            // ── Left: info + price + button ───────────────────────────
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if !item.description.isEmpty {
                    Text(item.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !item.optionGroups.isEmpty {
                    Label("Seçenekler mevcut", systemImage: "slider.horizontal.3")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                // Price + add button on the same row
                HStack(alignment: .center, spacing: 10) {
                    // Add button with cart-count badge
                    Button(action: onAdd) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.orange)
                            if cartCount > 0 {
                                Text("\(cartCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 18, height: 18)
                                    .background(Color.red)
                                    .cornerRadius(9)
                                    .offset(x: 5, y: -5)
                            }
                        }
                    }

                    // Price
                    if item.discountPercent > 0 {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("₺\(String(format: "%.2f", item.discountedPrice))")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.orange)
                            HStack(spacing: 4) {
                                Text("₺\(String(format: "%.2f", item.price))")
                                    .strikethrough()
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("-\(Int(item.discountPercent))%")
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(Color.red)
                                    .cornerRadius(4)
                            }
                        }
                    } else {
                        Text("₺\(String(format: "%.2f", item.price))")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // ── Right: image only ─────────────────────────────────────
            if let urlStr = item.imageUrl, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(width: 82, height: 82)
                            .cornerRadius(12)
                            .clipped()
                    default:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray5))
                            .frame(width: 82, height: 82)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
    }
}

