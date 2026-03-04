import SwiftUI

// MARK: - Owner Tab

private enum OwnerTab: Int, CaseIterable {
    case orders = 0, menu = 1, coupons = 2, info = 3, report = 4
    var title: String {
        switch self {
        case .orders:  return "Siparişler"
        case .menu:    return "Menü"
        case .coupons: return "Kuponlar"
        case .info:    return "Bilgiler"
        case .report:  return "Raporlar"
        }
    }
    var icon: String {
        switch self {
        case .orders:  return "list.clipboard"
        case .menu:    return "fork.knife"
        case .coupons: return "ticket.fill"
        case .info:    return "pencil.circle"
        case .report:  return "chart.bar.fill"
        }
    }
}

// MARK: - StoreDashboardView

struct StoreDashboardView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var restaurant: Restaurant?
    @State private var isLoading = true
    @State private var selectedTab: OwnerTab = .orders
    @State private var showingCreateSheet = false
    @State private var showingReviewsPanel = false
    // Hoisted here so the listener survives tab switches
    @State private var liveOrders: [Order] = []
    @State private var ordersListenerReg: ListenerRegistration?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView("Yükleniyor...")
                Spacer()
            } else if let restaurant = Binding($restaurant) {
                ownerDashboardContent(restaurant: restaurant)
            } else {
                // ── No restaurant: create one ───────────────────────────
                NoRestaurantView(onCreateTapped: { showingCreateSheet = true })
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // ── Ortada: mağaza adı + oturum e-postası ─────────────────
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(restaurant?.name ?? "Mağaza Paneli")
                        .font(.headline)
                        .lineLimit(1)
                    if let email = viewModel.authService.currentUser?.email {
                        Text(email)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.authService.signOut()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Çıkış").font(.caption)
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showingCreateSheet) {
            CreateRestaurantSheet(viewModel: viewModel) { newRestaurant in
                self.restaurant = newRestaurant
                showingCreateSheet = false
            }
        }
        .onAppear { loadRestaurant() }
        .onDisappear { ordersListenerReg?.remove() }
    }

    @ViewBuilder
    private func ownerDashboardContent(restaurant: Binding<Restaurant>) -> some View {
        ZStack(alignment: .bottomTrailing) {
            currentTabContent(restaurant: restaurant)
            reviewsOverlay(restaurant: restaurant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OwnerTabBar(
                selectedTab: $selectedTab,
                pendingCount: liveOrders.filter { $0.status == .pending }.count,
                cancelRequestCount: liveOrders.filter { $0.cancelRequested }.count
            )
        }
    }

    @ViewBuilder
    private func currentTabContent(restaurant: Binding<Restaurant>) -> some View {
        switch selectedTab {
        case .orders:
            OwnerOrdersView(
                restaurant: restaurant.wrappedValue,
                orders: $liveOrders,
                viewModel: viewModel
            )
        case .menu:
            MenuManagementView(restaurant: restaurant, dataService: viewModel.dataService)
        case .coupons:
            OwnerCouponsView(restaurant: restaurant.wrappedValue, viewModel: viewModel)
        case .info:
            RestaurantInfoEditView(restaurant: restaurant, dataService: viewModel.dataService)
        case .report:
            SalesReportView(restaurant: restaurant.wrappedValue, viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func reviewsOverlay(restaurant: Binding<Restaurant>) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            if showingReviewsPanel {
                OwnerReviewsFloatingPanel(
                    restaurant: restaurant.wrappedValue,
                    viewModel: viewModel,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingReviewsPanel = false
                        }
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingReviewsPanel.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                    Text("Yorumlar")
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                )
                .cornerRadius(10)
                .shadow(color: .black.opacity(0.08), radius: 5, x: 0, y: 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 12)
        .padding(.bottom, 84)
    }

    private func loadRestaurant() {
        isLoading = true
        // GET /restaurants/my — token üzerinden doğrudan sahip restoranı döndürür.
        // managedRestaurantId'ye bağımlı olmaz, logout/login sonrası da çalışır.
        viewModel.dataService.fetchMyRestaurant { fetched in
            restaurant = fetched
            isLoading = false
            guard let rid = fetched?.id else { return }
            // Start persistent real-time listener for orders
            ordersListenerReg?.remove()
            ordersListenerReg = viewModel.orderService.listenRestaurantOrders(restaurantId: rid) { orders in
                liveOrders = orders
            }
        }
    }
}

private struct OwnerReviewsFloatingPanel: View {
    let restaurant: Restaurant
    @ObservedObject var viewModel: AppViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Müşteri Yorumları")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            OwnerReviewsView(restaurant: restaurant, viewModel: viewModel)
        }
        .frame(width: 340)
        .frame(maxHeight: 500)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
}

// MARK: - OwnerTabBar

private struct OwnerTabBar: View {
    @Binding var selectedTab: OwnerTab
    var pendingCount: Int = 0
    var cancelRequestCount: Int = 0

    private var totalBadge: Int { pendingCount + cancelRequestCount }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                Spacer()
                ForEach(OwnerTab.allCases, id: \.rawValue) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
                    } label: {
                        VStack(spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: tab.icon).font(.system(size: 22))
                                    .scaleEffect(selectedTab == tab ? 1.1 : 1.0)
                                if tab == .orders && totalBadge > 0 {
                                    Text("\(totalBadge)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(3)
                                        .background(cancelRequestCount > 0 ? Color.orange : Color.red)
                                        .clipShape(Circle())
                                        .offset(x: 8, y: -6)
                                }
                            }
                            Text(tab.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        }
                        .foregroundColor(selectedTab == tab ? .orange : Color(.systemGray))
                        .frame(minWidth: 60)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .padding(.top, 8).padding(.bottom, 12)
            .background(Color(.systemBackground).ignoresSafeArea(edges: .bottom))
        }
    }
}

// MARK: - NoRestaurantView

private struct NoRestaurantView: View {
    let onCreateTapped: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "storefront").font(.system(size: 64)).foregroundColor(.orange.opacity(0.7))
            Text("Henüz bir mağazanız yok").font(.title2).fontWeight(.semibold)
            Text("Mağazanızı oluşturun ve menünüzü yönetmeye başlayın.")
                .multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)
            Button { onCreateTapped() } label: {
                Label("Mağaza Oluştur", systemImage: "plus.circle.fill")
                    .font(.headline).foregroundColor(.white)
                    .padding().frame(maxWidth: .infinity)
                    .background(Color.orange).cornerRadius(12)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
    }
}

// MARK: - CreateRestaurantSheet

struct CreateRestaurantSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let onCreated: (Restaurant) -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var cuisineType = ""
    @State private var deliveryTime = "30-45 dk"
    @State private var minOrder = ""
    @State private var imageUrl = ""
    @State private var city = ""
    @State private var showingCityPicker = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !cuisineType.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationView {
            Form {
                Section("Mağaza Bilgileri") {
                    TextField("Mağaza adı *", text: $name)
                    TextField("Mutfak türü * (ör: Burger, Pizza)", text: $cuisineType)
                    ZStack(alignment: .topLeading) {
                        if description.isEmpty {
                            Text("Açıklama")
                                .foregroundColor(Color(.placeholderText))
                                .padding(.top, 8).padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $description).frame(minHeight: 80, maxHeight: 120)
                    }
                }
                Section("Teslimat") {
                    TextField("Teslimat süresi (ör: 30-45 dk)", text: $deliveryTime)
                    TextField("Min. sipariş tutarı (₺)", text: $minOrder).keyboardType(.decimalPad)
                }
                Section("Görsel") {
                    TextField("Kapak görseli URL", text: $imageUrl).textInputAutocapitalization(.never)
                }
                Section("Konum") {
                    Button { showingCityPicker = true } label: {
                        HStack {
                            Text("Mağaza İli")
                            Spacer()
                            Text(city.isEmpty ? "Seçiniz" : city)
                                .foregroundColor(city.isEmpty ? .secondary : .primary)
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundColor(.red).font(.caption) }
                }
            }
            .navigationTitle("Mağaza Oluştur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading { ProgressView() } else {
                        Button("Oluştur") { createRestaurant() }.disabled(!isValid)
                    }
                }
            }
            .sheet(isPresented: $showingCityPicker) {
                CityPickerSheet(selectedCity: $city)
            }
        }
    }

    private func createRestaurant() {
        guard let uid = viewModel.authService.currentUser?.id else { return }
        isLoading = true
        errorMessage = nil
        let restaurant = Restaurant(
            id: UUID().uuidString, name: name.trimmingCharacters(in: .whitespaces),
            ownerId: uid, description: description,
            cuisineType: cuisineType.trimmingCharacters(in: .whitespaces),
            imageUrl: imageUrl.isEmpty ? nil : imageUrl,
            rating: 0, deliveryTime: deliveryTime.isEmpty ? "30-45 dk" : deliveryTime,
            minOrderAmount: Double(minOrder) ?? 0,
            menu: [], isActive: true,
            city: city.isEmpty ? nil : city
        )
        viewModel.dataService.createRestaurantForOwner(restaurant: restaurant, ownerUid: uid) { error in
            isLoading = false
            if let error { errorMessage = error.localizedDescription } else { onCreated(restaurant) }
        }
    }
}

// MARK: - MenuManagementView

struct MenuManagementView: View {
    @Binding var restaurant: Restaurant
    let dataService: DataService

    @State private var showingAddItem = false
    @State private var editingItem: MenuItem?
    @State private var isSaving = false
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var selectedCategory: String = "Tümü"

    private var categories: [String] {
        let cats = restaurant.menu.map { $0.category }
        return ["Tümü"] + Array(Set(cats)).sorted()
    }

    private var filteredMenu: [MenuItem] {
        selectedCategory == "Tümü" ? restaurant.menu : restaurant.menu.filter { $0.category == selectedCategory }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header info
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(restaurant.menu.count) ürün").font(.headline)
                    Text("Mağaza: \(restaurant.isActive ? "Açık ✓" : "Kapalı ✗")")
                        .font(.caption).foregroundColor(restaurant.isActive ? .green : .red)
                }
                Spacer()
                Button { showingAddItem = true } label: {
                    Label("Ürün Ekle", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.orange).cornerRadius(10)
                }
            }
            .padding()

            // Category filter
            if categories.count > 2 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { cat in
                            Button { selectedCategory = cat } label: {
                                Text(cat).font(.caption).fontWeight(.medium)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(selectedCategory == cat ? Color.orange : Color(.systemGray6))
                                    .foregroundColor(selectedCategory == cat ? .white : .primary)
                                    .cornerRadius(20)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 6)
            }

            Divider()

            if restaurant.menu.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "fork.knife.circle").font(.system(size: 50)).foregroundColor(.gray)
                    Text("Henüz ürün eklenmedi").foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(filteredMenu) { item in
                        MenuItemRow(item: item,
                            onToggleAvailability: { toggleAvailability(item) },
                            onEdit: { editingItem = item }
                        )
                    }
                    .onDelete { offsets in deleteItems(offsets, from: filteredMenu) }
                }
                .listStyle(.plain)
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddEditMenuItemView(item: nil) { newItem in
                let previousMenu = restaurant.menu
                restaurant.menu.append(newItem)
                saveMenu(previousMenu: previousMenu)
            }
        }
        .sheet(item: $editingItem) { item in
            AddEditMenuItemView(item: item) { updated in
                if let idx = restaurant.menu.firstIndex(where: { $0.id == updated.id }) {
                    let previousMenu = restaurant.menu
                    restaurant.menu[idx] = updated
                    saveMenu(previousMenu: previousMenu)
                }
            }
        }
        .alert(alertMessage, isPresented: $showingAlert) { Button("Tamam", role: .cancel) {} }
    }

    private func toggleAvailability(_ item: MenuItem) {
        if let idx = restaurant.menu.firstIndex(where: { $0.id == item.id }) {
            let previousMenu = restaurant.menu
            restaurant.menu[idx].isAvailable.toggle()
            saveMenu(previousMenu: previousMenu)
        }
    }

    private func deleteItems(_ offsets: IndexSet, from list: [MenuItem]) {
        let previousMenu = restaurant.menu
        let idsToDelete = offsets.map { list[$0].id }
        restaurant.menu.removeAll { idsToDelete.contains($0.id) }
        saveMenu(previousMenu: previousMenu)
    }

    private func saveMenu(previousMenu: [MenuItem]? = nil) {
        guard !isSaving else { return }
        isSaving = true

        dataService.updateRestaurantMenu(restaurantId: restaurant.id, menu: restaurant.menu) { error in
            isSaving = false
            if let error {
                // Son değişiklikleri geri al (optimistic UI rollback)
                if let previousMenu {
                    restaurant.menu = previousMenu
                }
                alertMessage = friendlySaveErrorMessage(error)
                showingAlert = true
            }
        }
    }

    private func friendlySaveErrorMessage(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized(_):
                return "Oturum süreniz dolmuş. Lütfen tekrar giriş yapın."
            case .forbidden:
                return "Bu mağaza için ürün ekleme yetkiniz yok."
            case .serverError(let code, _):
                if code >= 500 {
                    return "Sunucu şu anda ürün kaydetme işlemini tamamlayamadı. Lütfen birazdan tekrar deneyin."
                }
                return "Ürün kaydedilemedi. Lütfen girdiğiniz alanları kontrol edin."
            default:
                return apiError.localizedDescription
            }
        }
        return "Ürün kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin."
    }
}

// MARK: - MenuItemRow

private struct MenuItemRow: View {
    let item: MenuItem
    let onToggleAvailability: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            // ── Left: info ────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 5) {
                // Name + discount badge
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if item.discountPercent > 0 {
                        Text("-\(Int(item.discountPercent))%")
                            .font(.caption2.weight(.bold)).foregroundColor(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.red).cornerRadius(4)
                    }
                }

                // Category chip
                Text(item.category)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)

                // Description
                if !item.description.isEmpty {
                    Text(item.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                // Price row
                HStack(spacing: 6) {
                    if item.discountPercent > 0 {
                        Text("₺\(String(format: "%.2f", item.discountedPrice))")
                            .font(.subheadline.weight(.bold)).foregroundColor(.orange)
                        Text("₺\(String(format: "%.2f", item.price))")
                            .font(.caption).strikethrough().foregroundColor(.secondary)
                    } else {
                        Text("₺\(String(format: "%.2f", item.price))")
                            .font(.subheadline.weight(.bold)).foregroundColor(.orange)
                    }
                }

                // Option groups hint
                if !item.optionGroups.isEmpty {
                    Label("\(item.optionGroups.count) seçenek grubu", systemImage: "slider.horizontal.3")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }

            Spacer()

            // ── Right: image + controls ───────────────────────────────
            VStack(alignment: .center, spacing: 8) {
                // Thumbnail
                Group {
                    if let url = item.imageUrl, !url.isEmpty, let parsed = URL(string: url) {
                        AsyncImage(url: parsed) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                Color.orange.opacity(0.12)
                                    .overlay(Image(systemName: "photo").foregroundColor(.orange.opacity(0.5)))
                            }
                        }
                    } else {
                        Color.orange.opacity(0.10)
                            .overlay(Image(systemName: "fork.knife").font(.title3).foregroundColor(.orange.opacity(0.4)))
                    }
                }
                .frame(width: 76, height: 76)
                .cornerRadius(12)
                .clipped()

                // Edit + toggle
                HStack(spacing: 10) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title3).foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)

                    Toggle("", isOn: Binding(
                        get: { item.isAvailable },
                        set: { _ in onToggleAvailability() }
                    ))
                    .labelsHidden().scaleEffect(0.8)
                }
            }
            .frame(minWidth: 76)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .opacity(item.isAvailable ? 1 : 0.5)
    }
}

// MARK: - AddEditMenuItemView

struct AddEditMenuItemView: View {
    let item: MenuItem?
    let onSave: (MenuItem) -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var price = ""
    @State private var imageUrl = ""
    @State private var category = "Ana Yemekler"
    @State private var discountPercent: Double = 0
    @State private var isAvailable = true
    @State private var optionGroups: [MenuItemOptionGroup] = []
    @State private var suggestedItemIds: [String] = []
    @State private var showingAddOptionGroup = false
    @Environment(\.dismiss) private var dismiss

    let categories = ["Başlangıçlar", "Çorbalar", "Salatalar", "Ana Yemekler",
                      "Hamburger & Sandviç", "Pizza & Pide", "Makarna",
                      "Tatlılar", "İçecekler", "Atıştırmalıklar", "Diğer"]

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && Double(price) != nil }

    var body: some View {
        NavigationView {
            Form {
                Section("Ürün Bilgileri") {
                    TextField("Ürün adı *", text: $name)
                    ZStack(alignment: .topLeading) {
                        if description.isEmpty {
                            Text("Açıklama")
                                .foregroundColor(Color(.placeholderText))
                                .padding(.top, 8).padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $description).frame(minHeight: 80, maxHeight: 120)
                    }
                    Picker("Kategori", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }
                }

                Section("Fiyat") {
                    HStack {
                        Text("₺")
                        TextField("0.00", text: $price).keyboardType(.decimalPad)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("İndirim")
                            Spacer()
                            Text(discountPercent > 0 ? "-%\(Int(discountPercent))" : "Yok")
                                .fontWeight(.semibold)
                                .foregroundColor(discountPercent > 0 ? .red : .secondary)
                        }
                        Slider(value: $discountPercent, in: 0...70, step: 5)
                            .tint(.red)
                        if let p = Double(price), discountPercent > 0 {
                            Text("İndirimli fiyat: ₺\(String(format: "%.2f", p * (1 - discountPercent / 100)))")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                Section("Görsel") {
                    TextField("Görsel URL (opsiyonel)", text: $imageUrl)
                        .textInputAutocapitalization(.never).keyboardType(.URL)

                    if !imageUrl.isEmpty, let url = URL(string: imageUrl) {
                        VStack(spacing: 0) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFill()
                                case .failure:
                                    Color(.systemGray5)
                                        .overlay(
                                            Label("Görsel yüklenemedi", systemImage: "exclamationmark.triangle")
                                                .font(.caption).foregroundColor(.secondary)
                                        )
                                default:
                                    Color(.systemGray6)
                                        .overlay(ProgressView())
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                            .clipped()
                        }
                        .cornerRadius(10)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    }
                }

                Section("Durum") {
                    Toggle("Satışa açık", isOn: $isAvailable)
                }

                Section("Seçenek Grupları") {
                    ForEach(optionGroups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(group.name).fontWeight(.medium)
                                    Text(group.type == .singleSelect ? "Tek seçim" : "Çok seçim")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if group.isRequired {
                                    Text("Zorunlu").font(.caption2).foregroundColor(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.red).cornerRadius(4)
                                }
                            }
                            Text(group.options.map { $0.name }.joined(separator: ", "))
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .onDelete { optionGroups.remove(atOffsets: $0) }
                    Button { showingAddOptionGroup = true } label: {
                        Label("Seçenek Grubu Ekle", systemImage: "plus.circle")
                            .foregroundColor(.orange)
                    }
                }
            }
            .navigationTitle(item == nil ? "Ürün Ekle" : "Ürünü Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }.disabled(!isValid)
                }
            }
            .onAppear { prefill() }
            .sheet(isPresented: $showingAddOptionGroup) {
                AddOptionGroupSheet { group in optionGroups.append(group) }
            }
        }
    }

    private func prefill() {
        guard let item else { return }
        name = item.name; description = item.description
        price = String(format: "%.2f", item.price)
        imageUrl = item.imageUrl ?? ""; category = item.category
        discountPercent = item.discountPercent; isAvailable = item.isAvailable
        optionGroups = item.optionGroups
        suggestedItemIds = item.suggestedItemIds
    }

    private func save() {
        guard let priceValue = Double(price) else { return }
        let saved = MenuItem(
            id: item?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespaces),
            description: description,
            price: priceValue,
            imageUrl: imageUrl.isEmpty ? nil : imageUrl,
            category: category,
            discountPercent: discountPercent,
            isAvailable: isAvailable,
            optionGroups: optionGroups,
            suggestedItemIds: suggestedItemIds
        )
        onSave(saved)
        dismiss()
    }
}

// MARK: - AddOptionGroupSheet

struct AddOptionGroupSheet: View {
    let onSave: (MenuItemOptionGroup) -> Void
    @Environment(\..dismiss) private var dismiss

    @State private var groupName = ""
    @State private var groupType: OptionGroupType = .singleSelect
    @State private var isRequired = false
    @State private var maxSelections = 1
    @State private var options: [MenuItemOption] = []
    @State private var newOptionName = ""
    @State private var newOptionPrice = ""
    @State private var newOptionIsDefault = false

    private var isValid: Bool { !groupName.trimmingCharacters(in: .whitespaces).isEmpty && !options.isEmpty }

    var body: some View {
        NavigationView {
            Form {
                Section("Grup Bilgileri") {
                    TextField("Grup adı (ör: Acılık, Ekstralar)", text: $groupName)
                    Picker("Tür", selection: $groupType) {
                        Text("Tek Seçim (Radyo)").tag(OptionGroupType.singleSelect)
                        Text("Çok Seçim (Checkbox)").tag(OptionGroupType.multiSelect)
                    }
                    Toggle("Zorunlu seçim", isOn: $isRequired)
                    if groupType == .multiSelect {
                        Stepper("Maks seçim: \(maxSelections)", value: $maxSelections, in: 1...10)
                    }
                }

                Section("Seçenekler") {
                    ForEach(options) { opt in
                        HStack {
                            Text(opt.name)
                            Spacer()
                            if opt.extraPrice > 0 { Text("+₺\(opt.extraPrice, specifier: ".2f")").foregroundColor(.secondary) }
                            if opt.isDefault { Image(systemName: "checkmark").foregroundColor(.orange) }
                        }
                    }
                    .onDelete { options.remove(atOffsets: $0) }

                    HStack {
                        TextField("Seçenek adı", text: $newOptionName)
                        TextField("+Fiyat", text: $newOptionPrice).keyboardType(.decimalPad).frame(width: 60)
                        Toggle("", isOn: $newOptionIsDefault).labelsHidden()
                        Button {
                            guard !newOptionName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            let opt = MenuItemOption(
                                name: newOptionName.trimmingCharacters(in: .whitespaces),
                                extraPrice: Double(newOptionPrice) ?? 0,
                                isDefault: newOptionIsDefault
                            )
                            options.append(opt)
                            newOptionName = ""; newOptionPrice = ""; newOptionIsDefault = false
                        } label: {
                            Image(systemName: "plus.circle.fill").foregroundColor(.orange)
                        }
                    }
                    Text("Fiyat alanı: 0 ise dahil. Toggle: Varsayılan seçili\n(Önce adı yazın, + butonuna basın)").font(.caption2).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Seçenek Grubu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") {
                        let group = MenuItemOptionGroup(
                            name: groupName.trimmingCharacters(in: .whitespaces),
                            type: groupType,
                            isRequired: isRequired,
                            minSelections: isRequired ? 1 : 0,
                            maxSelections: groupType == .multiSelect ? maxSelections : 1,
                            options: options
                        )
                        onSave(group)
                        dismiss()
                    }.disabled(!isValid)
                }
            }
        }
    }
}

// MARK: - RestaurantInfoEditView

struct RestaurantInfoEditView: View {
    @Binding var restaurant: Restaurant
    let dataService: DataService

    @State private var draftName = ""
    @State private var draftDescription = ""
    @State private var draftCuisine = ""
    @State private var draftDelivery = ""
    @State private var draftMinOrder = ""
    @State private var draftImageUrl = ""
    @State private var isActive = true
    @State private var allowsPickup = false
    @State private var allowsCashOnDelivery = false
    @State private var draftCity = ""
    @State private var showingCityPickerInfo = false
    @State private var isSaving = false
    @State private var successMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Form {
                    Section("Mağaza Bilgileri") {
                        TextField("Mağaza adı", text: $draftName)
                        TextField("Mutfak türü", text: $draftCuisine)
                        ZStack(alignment: .topLeading) {
                            if draftDescription.isEmpty {
                                Text("Açıklama")
                                    .foregroundColor(Color(.placeholderText))
                                    .padding(.top, 8).padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $draftDescription).frame(minHeight: 80, maxHeight: 120)
                        }
                    }
                    Section("Teslimat") {
                        TextField("Teslimat süresi (ör: 30-45 dk)", text: $draftDelivery)
                        HStack {
                            Text("Min. sipariş ₺")
                            TextField("0", text: $draftMinOrder).keyboardType(.decimalPad)
                        }
                    }
                    Section("Görsel") {
                        TextField("Kapak görseli URL", text: $draftImageUrl).textInputAutocapitalization(.never)
                        if let url = URL(string: draftImageUrl), !draftImageUrl.isEmpty {
                            AsyncImage(url: url) { img in img.resizable().scaledToFit().frame(height: 140).cornerRadius(10) }
                                placeholder: { ProgressView() }
                        }
                    }
                    Section("Durum") {
                        Toggle("Mağaza Açık", isOn: $isActive)
                            .tint(.green)
                        Text(isActive ? "Müşteriler siparişi görebilir ve sipariş verebilir." : "Mağaza müşterilere görünmez.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Section("Sipariş Seçenekleri") {
                        Toggle("Gel-Al aktif", isOn: $allowsPickup).tint(.blue)
                        Toggle("Kapıda Ödeme aktif", isOn: $allowsCashOnDelivery).tint(.green)
                        Text("Kapıda ödeme açıksa müşteriler nakit veya kart ile kapıda ödeme yapabilir.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Section("Konum") {
                        Button { showingCityPickerInfo = true } label: {
                            HStack {
                                Text("Mağaza İli")
                                Spacer()
                                Text(draftCity.isEmpty ? "Seçiniz" : draftCity)
                                    .foregroundColor(draftCity.isEmpty ? .secondary : .primary)
                                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                    Section {
                        if let err = errorMessage {
                            Text(err).foregroundColor(.red).font(.caption)
                        }
                        if let suc = successMessage {
                            Text(suc).foregroundColor(.green).font(.caption)
                        }
                        Button { saveInfo() } label: {
                            if isSaving { ProgressView() } else {
                                Text("Değişiklikleri Kaydet")
                                    .font(.headline).foregroundColor(.white)
                                    .frame(maxWidth: .infinity).padding()
                                    .background(Color.orange).cornerRadius(12)
                            }
                        }
                        .disabled(isSaving)
                    }
                }
                .frame(minHeight: 600)
            }
        }
        .onAppear { prefill() }
        .sheet(isPresented: $showingCityPickerInfo) {
            CityPickerSheet(selectedCity: $draftCity)
        }
    }

    private func prefill() {
        draftName = restaurant.name; draftDescription = restaurant.description
        draftCuisine = restaurant.cuisineType; draftDelivery = restaurant.deliveryTime
        draftMinOrder = String(format: "%.0f", restaurant.minOrderAmount)
        draftImageUrl = restaurant.imageUrl ?? ""; isActive = restaurant.isActive
        allowsPickup = restaurant.allowsPickup
        allowsCashOnDelivery = restaurant.allowsCashOnDelivery
        draftCity = restaurant.city ?? ""
    }

    private func saveInfo() {
        isSaving = true; errorMessage = nil; successMessage = nil
        var updated = restaurant
        updated = Restaurant(
            id: restaurant.id,
            name: draftName.trimmingCharacters(in: .whitespaces),
            ownerId: restaurant.ownerId,
            description: draftDescription,
            cuisineType: draftCuisine.trimmingCharacters(in: .whitespaces),
            imageUrl: draftImageUrl.isEmpty ? nil : draftImageUrl,
            rating: restaurant.rating, deliveryTime: draftDelivery,
            minOrderAmount: Double(draftMinOrder) ?? 0,
            menu: restaurant.menu, isActive: isActive,
            city: draftCity.isEmpty ? nil : draftCity,
            allowsPickup: allowsPickup,
            allowsCashOnDelivery: allowsCashOnDelivery,
            successfulOrderCount: restaurant.successfulOrderCount,
            averageRating: restaurant.averageRating,
            ratingCount: restaurant.ratingCount
        )
        dataService.updateRestaurant(restaurant: updated) { error in
            isSaving = false
            if let error { errorMessage = error.localizedDescription } else {
                restaurant = updated
                successMessage = "Kaydedildi ✓"
            }
        }
    }
}

// MARK: - OwnerStatsView

struct OwnerStatsView: View {
    let restaurant: Restaurant

    private var totalItems: Int { restaurant.menu.count }
    private var availableItems: Int { restaurant.menu.filter { $0.isAvailable }.count }
    private var discountedItems: Int { restaurant.menu.filter { $0.discountPercent > 0 }.count }
    private var avgPrice: Double {
        guard !restaurant.menu.isEmpty else { return 0 }
        return restaurant.menu.map { $0.price }.reduce(0, +) / Double(restaurant.menu.count)
    }
    private var categoryBreakdown: [(String, Int)] {
        var counts: [String: Int] = [:]
        restaurant.menu.forEach { counts[$0.category, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status banner
                HStack {
                    Image(systemName: restaurant.isActive ? "checkmark.circle.fill" : "xmark.circle.fill")
                    Text(restaurant.isActive ? "Mağaza Açık" : "Mağaza Kapalı")
                        .fontWeight(.semibold)
                }
                .foregroundColor(restaurant.isActive ? .green : .red)
                .padding().frame(maxWidth: .infinity)
                .background((restaurant.isActive ? Color.green : Color.red).opacity(0.1))
                .cornerRadius(12)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    OwnerStatCard(title: "Toplam Ürün", value: "\(totalItems)", icon: "fork.knife", color: .orange)
                    OwnerStatCard(title: "Satışta", value: "\(availableItems)", icon: "checkmark.circle", color: .green)
                    OwnerStatCard(title: "İndirimli", value: "\(discountedItems)", icon: "tag.fill", color: .red)
                    OwnerStatCard(title: "Ort. Fiyat", value: "₺\(String(format: "%.0f", avgPrice))", icon: "turkishlirasign.circle", color: .blue)
                }

                if !categoryBreakdown.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Kategoriler").font(.headline).padding(.horizontal)
                        ForEach(categoryBreakdown, id: \.0) { cat, count in
                            HStack {
                                Text(cat).font(.subheadline)
                                Spacer()
                                Text("\(count) ürün").font(.caption).foregroundColor(.secondary)
                                // Mini bar
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.orange)
                                    .frame(width: CGFloat(count) / CGFloat(totalItems) * 80, height: 8)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6)).cornerRadius(12)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Mağaza Bilgileri").font(.headline)
                    infoRow("Mutfak Türü", restaurant.cuisineType)
                    infoRow("Teslimat Süresi", restaurant.deliveryTime)
                    infoRow("Min. Sipariş", "₺\(String(format: "%.0f", restaurant.minOrderAmount))")
                    infoRow("Puan", String(format: "%.1f ⭐", restaurant.rating))
                }
                .padding().background(Color(.systemGray6)).cornerRadius(12)
            }
            .padding()
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary).font(.subheadline)
            Spacer()
            Text(value).fontWeight(.medium).font(.subheadline)
        }
    }
}

private struct OwnerStatCard: View {
    let title: String; let value: String; let icon: String; let color: Color
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 28)).foregroundColor(color)
            Text(value).font(.title2).fontWeight(.bold)
            Text(title).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .padding().frame(maxWidth: .infinity)
        .background(color.opacity(0.08)).cornerRadius(12)
    }
}

struct OwnerReviewsView: View {
    let restaurant: Restaurant
    @ObservedObject var viewModel: AppViewModel

    @State private var reviews: [OrderReview] = []
    @State private var isLoading = true
    @State private var replyingReview: OrderReview?
    @State private var replyText: String = ""
    @State private var isSendingReply = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView("Yorumlar yükleniyor...")
                Spacer()
            } else if reviews.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 46))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("Henüz yorum yok")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(reviews) { review in
                            VStack(alignment: .leading, spacing: 8) {
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
                                }

                                if let ownerReply = review.ownerReply, !ownerReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Yanıtınız")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.orange)
                                        Text(ownerReply)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(8)
                                    .background(Color.orange.opacity(0.08))
                                    .cornerRadius(8)
                                } else {
                                    Button {
                                        replyText = ""
                                        replyingReview = review
                                    } label: {
                                        Label("Yanıtla", systemImage: "arrowshape.turn.up.left")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .background(Color.orange.opacity(0.1))
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(12)
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .onAppear { loadReviews() }
        .refreshable { loadReviews() }
        .alert("Hata", isPresented: .constant(errorMessage != nil)) {
            Button("Tamam") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $replyingReview) { review in
            NavigationView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Müşteri Yorumu")
                        .font(.headline)
                    Text(review.comment.isEmpty ? "(Yorum metni yok)" : review.comment)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)

                    Text("Tek seferlik yanıt")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: $replyText)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)

                    Spacer()

                    Button {
                        sendReply(review: review)
                    } label: {
                        HStack {
                            if isSendingReply {
                                ProgressView().tint(.white)
                            }
                            Text(isSendingReply ? "Gönderiliyor..." : "Yanıtı Gönder")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.white)
                        .background(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.orange)
                        .cornerRadius(12)
                    }
                    .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingReply)
                }
                .padding()
                .navigationTitle("Yoruma Yanıt")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Kapat") { replyingReview = nil }
                    }
                }
            }
        }
    }

    private func loadReviews() {
        isLoading = true
        viewModel.orderService.fetchReviews(restaurantId: restaurant.id) { list in
            DispatchQueue.main.async {
                self.reviews = list
                self.isLoading = false
            }
        }
    }

    private func sendReply(review: OrderReview) {
        let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSendingReply = true
        viewModel.orderService.replyToReview(restaurantId: restaurant.id, reviewId: review.id, reply: trimmed) { error in
            DispatchQueue.main.async {
                self.isSendingReply = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.replyingReview = nil
                self.loadReviews()
            }
        }
    }
}

