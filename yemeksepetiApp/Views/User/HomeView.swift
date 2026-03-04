import SwiftUI

// MARK: - HomeView

struct HomeView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var restaurantVM = RestaurantListViewModel(api: RestaurantAPIService())
    @State private var showingAddressPicker = false
    @State private var showingAddAddress = false
    @State private var savedAddresses: [UserAddress] = []
    @State private var selectedAddress: UserAddress?
    // fallback: city picked without an address (onboarding path)
    @State private var showingCityPicker = false
    @State private var pickerCity = ""
    @State private var manualCity: String = ""

    // ── CF Recommendations ──────────────────────────────────────────────────
    @State private var cfRecommendations: [CFRecommendationItem] = []
    @State private var cfLabel: String = ""
    @State private var cfTimeSegment: String = ""
    @State private var isLoadingRecs = false

    private var selectedCity: String? {
        if let city = selectedAddress?.city, !city.isEmpty { return city }
        if !manualCity.isEmpty { return manualCity }
        let city = viewModel.authService.currentUser?.city
        return (city?.isEmpty == false) ? city : nil
    }

    private var needsCityOnboarding: Bool {
        viewModel.authService.isAuthenticated && selectedCity == nil
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !needsCityOnboarding { searchHeader }
                contentArea
            }
            .animation(AppMotion.standard, value: needsCityOnboarding)
            .animation(AppMotion.standard, value: restaurantVM.isLoading)
            .animation(AppMotion.spring, value: restaurantVM.restaurants.count)
            .navigationTitle("Yemeksepeti")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                restaurantVM.cityFilter = selectedCity
                restaurantVM.loadIfNeeded()
                refreshAddresses()
                loadRecommendations()
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
            .onChange(of: selectedAddress?.id) { newId in
                if let newId { viewModel.selectedAddressId = newId }
                restaurantVM.cityFilter = selectedCity
            }
            .onChange(of: viewModel.selectedAddressId) { newId in
                guard let newId, newId != selectedAddress?.id else { return }
                if let match = savedAddresses.first(where: { $0.id == newId }) {
                    selectedAddress = match
                }
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

    // MARK: - Header (address + search + cuisine chips)

    @ViewBuilder
    private var searchHeader: some View {
        addressBar
            .padding(.horizontal)
            .padding(.top, 6)
            .padding(.bottom, 8)

        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.gray)
            TextField("Mağaza veya ürün ara...", text: $viewModel.globalSearchQuery)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit {
                    let q = viewModel.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard q.count >= 2 else { return }
                    viewModel.selectedTab = 1
                }
            if !viewModel.globalSearchQuery.isEmpty {
                Button { viewModel.globalSearchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.bottom, restaurantVM.availableCuisines.isEmpty ? 8 : 4)

        if !restaurantVM.availableCuisines.isEmpty {
            cuisineChips
        }

        Divider()
    }

    @ViewBuilder
    private var cuisineChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "Tümü", isActive: restaurantVM.cuisineFilter == nil) {
                    restaurantVM.cuisineFilter = nil
                }
                ForEach(restaurantVM.availableCuisines, id: \.self) { cuisine in
                    FilterChip(
                        label: cuisine,
                        isActive: restaurantVM.cuisineFilter == cuisine
                    ) {
                        restaurantVM.cuisineFilter =
                            restaurantVM.cuisineFilter == cuisine ? nil : cuisine
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        if needsCityOnboarding {
            cityOnboardingView
                .subtleCardTransition()
        } else if restaurantVM.isLoading {
            loadingView
                .subtleCardTransition()
        } else if restaurantVM.restaurants.isEmpty {
            emptyRestaurantsView
                .subtleCardTransition()
        } else {
            restaurantListView
                .subtleCardTransition()
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        Spacer()
        ProgressView("Mağazalar yükleniyor...")
        Spacer()
    }

    @ViewBuilder
    private var emptyRestaurantsView: some View {
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
                    .buttonStyle(PressScaleButtonStyle())
            } else {
                Text("Restoran bulunamadı").foregroundColor(.secondary)
            }
        }
        Spacer()
    }

    @ViewBuilder
    private var restaurantListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // ── Saat bazlı CF önerileri ─────────────────────────────────
                if isLoadingRecs {
                    recLoadingPlaceholder
                } else if !cfRecommendations.isEmpty {
                    recommendationsSection
                }

                ForEach(Array(restaurantVM.restaurants.enumerated()), id: \.element.id) { index, restaurant in
                    NavigationLink(destination: RestaurantDetailView(restaurant: restaurant, viewModel: viewModel)) {
                        RestaurantCard(restaurant: restaurant)
                    }
                    .buttonStyle(.plain)
                    .subtleCardTransition()
                    .onAppear { restaurantVM.prefetchIfNeeded(currentIndex: index) }
                }
                paginationFooter
            }
            .padding()
        }
        .refreshable { restaurantVM.reloadRestaurants() }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if restaurantVM.isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        } else if restaurantVM.hasMore {
            Button("Daha fazla yükle") { restaurantVM.loadMoreRestaurants() }
                .font(.subheadline)
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .buttonStyle(PressScaleButtonStyle())
        }
    }

    // MARK: - Recommendations Section

    @ViewBuilder
    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ── Başlık ──────────────────────────────────────────────────────
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: timeSegmentIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Senin İçin Öneriler")
                        .font(.system(size: 17, weight: .bold))
                    if !cfLabel.isEmpty {
                        Text(cfLabel)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if cfRecommendations.count > 3 {
                    Text("Tümü")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 4)

            // ── Paging Carousel ─────────────────────────────────────────────
            TabView {
                ForEach(cfRecommendations) { rec in
                    RecommendationCard(item: rec, viewModel: viewModel)
                        .padding(.horizontal, 6)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(height: 210)
        }
        .padding(.bottom, 10)
    }

    private var timeSegmentIcon: String {
        switch cfTimeSegment {
        case "breakfast":  return "sunrise.fill"
        case "lunch":      return "sun.max.fill"
        case "afternoon":  return "cup.and.saucer.fill"
        case "dinner":     return "moon.fill"
        case "late_night": return "moon.stars.fill"
        default:           return "fork.knife"
        }
    }

    // ── Yükleme Placeholder ─────────────────────────────────────────────────

    @ViewBuilder
    private var recLoadingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 140, height: 14)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.10))
                        .frame(width: 80, height: 10)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.10))
                .frame(height: 185)
                .overlay(
                    ProgressView()
                        .tint(.orange)
                )
        }
        .padding(.bottom, 10)
    }

    private func loadRecommendations() {
        guard !isLoadingRecs else { return }
        isLoadingRecs = true
        let recoService = RecommendationService()
        let city = selectedCity

        Task {
            do {
                let response: CFRecommendationResponse
                if viewModel.authService.isAuthenticated {
                    response = try await recoService.personalRecommendations(
                        city: city, topN: 15
                    )
                } else {
                    response = try await recoService.popularNow(city: city, topN: 10)
                }
                await MainActor.run {
                    cfRecommendations = response.items
                    cfLabel = response.label
                    cfTimeSegment = response.timeSegment
                    isLoadingRecs = false
                }
            } catch {
                await MainActor.run { isLoadingRecs = false }
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

    private func refreshAddresses(uid: String? = nil) {
        let resolvedUid = uid ?? viewModel.authService.currentUser?.id
        guard let resolvedUid else { return }
        viewModel.dataService.fetchAddresses(uid: resolvedUid) { addresses in
            savedAddresses = addresses

            // Shared id from checkout (or previous selection)
            let sharedId = viewModel.selectedAddressId

            if let sid = sharedId, let match = addresses.first(where: { $0.id == sid }) {
                selectedAddress = match
            } else if let current = selectedAddress, addresses.contains(where: { $0.id == current.id }) {
                selectedAddress = addresses.first(where: { $0.id == current.id })
            } else {
                selectedAddress = addresses.first(where: { $0.isDefault }) ?? addresses.first
            }

            // Sync shared id
            if let addr = selectedAddress {
                viewModel.selectedAddressId = addr.id
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
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text("\(max(0, restaurant.successfulOrderCount))+ başarılı sipariş")
                        .font(.caption2)
                        .foregroundColor(.secondary)
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

// MARK: - RecommendationCard

struct RecommendationCard: View {
    let item: CFRecommendationItem
    @ObservedObject var viewModel: AppViewModel

    private var menuItem: MenuItem { item.item.toMenuItem() }

    var body: some View {
        cardContent
    }

    private var cardContent: some View {
        ZStack(alignment: .bottomLeading) {
            // ── Arka plan görseli ───────────────────────────────────────
            Group {
                if let urlStr = item.item.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        case .empty:
                            shimmerPlaceholder
                        case .failure:
                            recImagePlaceholder
                        @unknown default:
                            recImagePlaceholder
                        }
                    }
                } else {
                    recImagePlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // ── Gradient overlay ────────────────────────────────────────
            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )

            // ── Alt bilgi alanı ─────────────────────────────────────────
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.item.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .shadow(radius: 2)

                    if let rName = item.item.restaurantName {
                        HStack(spacing: 4) {
                            Image(systemName: "storefront.fill")
                                .font(.system(size: 10))
                            Text(rName)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white.opacity(0.85))
                    }

                    // Fiyat
                    HStack(spacing: 6) {
                        if item.item.discountPercent > 0 {
                            Text("₺\(String(format: "%.0f", item.item.price))")
                                .font(.system(size: 12))
                                .strikethrough()
                                .foregroundColor(.white.opacity(0.55))
                            Text("₺\(String(format: "%.0f", item.item.price * (1 - item.item.discountPercent / 100)))")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.green)
                        } else {
                            Text("₺\(String(format: "%.0f", item.item.price))")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }

                Spacer()

                // ── Sağ taraf: Eşleşme ve kaynak rozeti ────────────────
                VStack(alignment: .trailing, spacing: 6) {
                    // Match yüzdesi
                    Text("\(Int(item.score * 100))%")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .clipShape(Capsule())

                    // Kaynak etiketi
                    if item.source.contains("cf") {
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 9))
                            Text("\(item.supporters)")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial.opacity(0.6))
                        .clipShape(Capsule())
                    } else if item.source == "popular" {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 9))
                            Text("Popüler")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial.opacity(0.6))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(14)

            // ── İndirim rozeti (sol üst) ────────────────────────────────
            if item.item.discountPercent > 0 {
                VStack {
                    HStack {
                        Text("-%\(Int(item.item.discountPercent))")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .padding(10)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 185)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    private var shimmerPlaceholder: some View {
        Color.gray.opacity(0.15)
            .overlay(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.2), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }

    private var recImagePlaceholder: some View {
        Color.orange.opacity(0.10)
            .overlay(
                Image(systemName: "fork.knife")
                    .font(.system(size: 34))
                    .foregroundColor(.orange.opacity(0.35))
            )
    }
}

// Corner radius helper
private extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

private struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
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
    @State private var loadedMenu: [MenuItem] = []
    @State private var reviews: [OrderReview] = []
    @State private var reviewsLoading = false
    @State private var showingReviewsSheet = false
    @State private var didLoadInitialData = false

    private var cart: CartViewModel { viewModel.cart }

    /// Uses freshly fetched detail endpoint menu; falls back to list data.
    private var effectiveMenu: [MenuItem] { loadedMenu.isEmpty ? restaurant.menu : loadedMenu }

    private var categories: [String] {
        Array(Set(effectiveMenu.filter(\.isAvailable).map(\.category))).sorted()
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

                        // ── Reviews entry ───────────────────────────────────
                        reviewsEntrySection

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
        .onAppear {
            guard !didLoadInitialData else { return }
            didLoadInitialData = true
            fetchMenuDetail()
        }
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
        .sheet(isPresented: $showingReviewsSheet) {
            if #available(iOS 16.0, *) {
                RestaurantReviewsSheet(
                    restaurantName: restaurant.name,
                    reviews: reviews,
                    isLoading: reviewsLoading,
                    onRefresh: { fetchReviews() }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            } else {
                RestaurantReviewsSheet(
                    restaurantName: restaurant.name,
                    reviews: reviews,
                    isLoading: reviewsLoading,
                    onRefresh: { fetchReviews() }
                )
            }
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

    @ViewBuilder
    private var reviewsEntrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Müşteri Yorumları", systemImage: "text.bubble")
                    .font(.headline.weight(.bold))
                Spacer()
                if reviewsLoading {
                    ProgressView().scaleEffect(0.85)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Button {
                showingReviewsSheet = true
                if reviews.isEmpty && !reviewsLoading {
                    fetchReviews()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(reviews.isEmpty ? "Yorumları Gör" : "Tüm Yorumları Gör (\(reviews.count))")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Color(.systemGroupedBackground))
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
        let items = effectiveMenu.filter { $0.category == category && $0.isAvailable }
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

    private func fetchMenuDetail() {
        viewModel.dataService.fetchRestaurant(id: restaurant.id) { detail in
            if let menu = detail?.menu, !menu.isEmpty {
                DispatchQueue.main.async { self.loadedMenu = menu }
            }
        }
    }

    private func fetchReviews() {
        reviewsLoading = true
        viewModel.orderService.fetchReviews(restaurantId: restaurant.id) { list in
            DispatchQueue.main.async {
                self.reviews = list
                self.reviewsLoading = false
            }
        }
    }

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
            effectiveMenu.first(where: { $0.id == id && $0.isAvailable })
        }
        if !available.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showingSuggested = true }
        }
    }
}

private struct RestaurantReviewsSheet: View {
    let restaurantName: String
    let reviews: [OrderReview]
    let isLoading: Bool
    let onRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView("Yorumlar yükleniyor...")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if reviews.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 42))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("Henüz yorum yok")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(reviews) { review in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text((review.userDisplayName ?? "Kullanıcı").isEmpty ? "Kullanıcı" : (review.userDisplayName ?? "Kullanıcı"))
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        HStack(spacing: 4) {
                                            Image(systemName: "star.fill").foregroundColor(.orange)
                                            Text(String(format: "%.1f", review.averageRating))
                                                .font(.caption.weight(.semibold))
                                        }
                                    }

                                    if !review.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(review.comment)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                    }

                                    if let ownerReply = review.ownerReply, !ownerReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Mağaza Yanıtı")
                                                .font(.caption.weight(.semibold))
                                                .foregroundColor(.orange)
                                            Text(ownerReply)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.orange.opacity(0.08))
                                        .cornerRadius(8)
                                    }
                                }
                                .padding(12)
                                .background(Color(.systemBackground))
                                .cornerRadius(10)
                            }
                        }
                        .padding(16)
                    }
                    .background(Color(.systemGroupedBackground))
                    .refreshable { onRefresh() }
                }
            }
            .navigationTitle("Yorumlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .onAppear {
            if reviews.isEmpty && !isLoading {
                onRefresh()
            }
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

