import SwiftUI

struct AdminUserListView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var searchQuery = ""
    @State private var allUsers: [AppUser] = []      // full list loaded on appear
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingRoleSheet = false
    @State private var activeUser: AppUser?          // captured before dialog closes
    @State private var showingRestaurantPicker = false
    @State private var availableRestaurants: [Restaurant] = []
    @State private var isLoadingRestaurants = false
    @State private var alertTitle = ""
    @State private var showingAlert = false

    // Client-side instant filter
    private var filteredUsers: [AppUser] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? allUsers : allUsers.filter { $0.email.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Search bar ───────────────────────────────────────────────────
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.gray)
                    TextField("Email ile ara...", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                if isLoading { ProgressView().padding(.trailing, 4) }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            // ── Error banner ─────────────────────────────────────────────────
            if let errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(errorMessage).font(.caption).foregroundColor(.orange)
                    Spacer()
                    Button("Tekrar Dene") { loadAllUsers() }.font(.caption).foregroundColor(.blue)
                }
                .padding(.horizontal).padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }

            // ── User list ────────────────────────────────────────────────────
            if isLoading && allUsers.isEmpty {
                Spacer()
                ProgressView("Kullanıcılar yükleniyor...")
                Spacer()
            } else if filteredUsers.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: allUsers.isEmpty ? "person.slash" : "magnifyingglass")
                        .font(.system(size: 44)).foregroundColor(.gray)
                    Text(allUsers.isEmpty ? "Henüz kullanıcı yok" : "Arama sonucu bulunamadı")
                        .foregroundColor(.secondary)
                    if !allUsers.isEmpty {
                        Text("Toplam \(allUsers.count) kullanıcı mevcut")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
            } else {
                List(filteredUsers) { user in
                    UserRow(user: user, onEdit: {
                        activeUser = user
                        showingRoleSheet = true
                    })
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(allUsers.isEmpty ? "Kullanıcı Yönetimi" : "Kullanıcılar (\(allUsers.count))")
        // ── Role action dialog ───────────────────────────────────────────────
        .confirmationDialog(
            activeUser.map { "İşlem: \($0.email)" } ?? "Kullanıcı İşlemleri",
            isPresented: $showingRoleSheet,
            titleVisibility: .visible
        ) {
            if let user = activeUser {
                Button("Süper Admin Yap") { updateUserRole(uid: user.id, role: .superAdmin) }
                Button("Mağaza Sahibi Yap…") { fetchRestaurantsForPicker(for: user) }
                Button("Normal Kullanıcı Yap") { updateUserRole(uid: user.id, role: .user) }
                Button("Kullanıcıyı Sil", role: .destructive) { deleteUser(uid: user.id) }
                Button("İptal", role: .cancel) { activeUser = nil }
            }
        }
        // ── Restaurant picker sheet ──────────────────────────────────────────
        .sheet(isPresented: $showingRestaurantPicker) {
            RestaurantPickerView(
                restaurants: availableRestaurants,
                isLoading: isLoadingRestaurants,
                dataService: viewModel.dataService,
                ownerUid: activeUser?.id ?? ""
            ) { restaurantId in
                if let user = activeUser {
                    updateUserToStoreOwner(uid: user.id, restaurantId: restaurantId)
                }
                showingRestaurantPicker = false
            }
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("Tamam", role: .cancel) {}
        }
        .onAppear { loadAllUsers() }
    }
    
    // MARK: - Data Actions

    private func loadAllUsers() {
        isLoading = true
        errorMessage = nil
        viewModel.authService.fetchAllUsers { users, error in
            isLoading = false
            if let error {
                errorMessage = error
            }
            allUsers = users
        }
    }

    func updateUserRole(uid: String, role: UserRole) {
        viewModel.authService.updateUserRole(uid: uid, role: role) { error in
            if let error {
                alertTitle = "Hata: \(error.localizedDescription)"
            } else {
                alertTitle = "Rol başarıyla güncellendi."
                loadAllUsers()
            }
            showingAlert = true
        }
    }

    func fetchRestaurantsForPicker(for user: AppUser) {
        activeUser = user        // capture before dialog dismisses
        isLoadingRestaurants = true
        showingRestaurantPicker = true
        viewModel.dataService.getAllRestaurantsForAdmin { restaurants in
            availableRestaurants = restaurants
            isLoadingRestaurants = false
        }
    }

    func updateUserToStoreOwner(uid: String, restaurantId: String) {
        viewModel.dataService.assignStoreOwner(uid: uid, restaurantId: restaurantId) { error in
            if let error {
                alertTitle = "Hata: \(error.localizedDescription)"
            } else {
                alertTitle = "Mağaza sahibi başarıyla atandı."
                loadAllUsers()
            }
            showingAlert = true
        }
    }

    func deleteUser(uid: String) {
        viewModel.authService.deleteUser(uid: uid) { error in
            if let error {
                alertTitle = "Silme hatası: \(error.localizedDescription)"
            } else {
                alertTitle = "Kullanıcı silindi."
                loadAllUsers()
            }
            showingAlert = true
        }
    }
}

struct UserRow: View {
    let user: AppUser
    let onEdit: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(user.email)
                    .font(.headline)
                HStack {
                    Image(systemName: iconForRole(user.role))
                    Text(user.role.rawValue)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
    
    func iconForRole(_ role: UserRole) -> String {
        switch role {
        case .superAdmin: return "shield.fill"
        case .storeOwner: return "briefcase.fill"
        case .user: return "person.fill"
        }
    }
}

struct RestaurantPickerView: View {
    let restaurants: [Restaurant]
    let isLoading: Bool
    let dataService: DataService
    let ownerUid: String
    let onSelect: (String) -> Void

    @State private var showingCreateSheet = false
    @Environment(\.dismiss) private var dismiss

    init(restaurants: [Restaurant], isLoading: Bool = false,
         dataService: DataService, ownerUid: String,
         onSelect: @escaping (String) -> Void) {
        self.restaurants = restaurants
        self.isLoading = isLoading
        self.dataService = dataService
        self.ownerUid = ownerUid
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Restoranlar yükleniyor...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        // ── Create new ────────────────────────────────────────
                        Section {
                            Button { showingCreateSheet = true } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2).foregroundColor(.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Yeni Mağaza Oluştur")
                                            .fontWeight(.semibold).foregroundColor(.orange)
                                        Text("Kullanıcı için yeni bir mağaza oluştur ve ata")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        // ── Existing restaurants ──────────────────────────────
                        if !restaurants.isEmpty {
                            Section(header: Text("Mevcut Mağazalar")) {
                                ForEach(restaurants) { restaurant in
                                    Button {
                                        onSelect(restaurant.id)
                                        dismiss()
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(restaurant.name)
                                                    .foregroundColor(.primary).fontWeight(.medium)
                                                if let ownerId = restaurant.ownerId {
                                                    Text("Sahip UID: \(ownerId.prefix(12))...")
                                                        .font(.caption).foregroundColor(.secondary)
                                                } else {
                                                    Text("Sahipsiz")
                                                        .font(.caption).foregroundColor(.orange)
                                                }
                                            }
                                            Spacer()
                                            Text(restaurant.isActive ? "Aktif" : "Pasif")
                                                .font(.caption)
                                                .padding(.horizontal, 8).padding(.vertical, 3)
                                                .background(restaurant.isActive ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                                .foregroundColor(restaurant.isActive ? .green : .red)
                                                .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                        } else {
                            Section {
                                HStack {
                                    Image(systemName: "building.2.slash").foregroundColor(.gray)
                                    Text("Henüz mağaza yok").foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Mağaza Ata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                AdminCreateRestaurantForUserSheet(
                    dataService: dataService,
                    ownerUid: ownerUid
                ) { newRestaurantId in
                    onSelect(newRestaurantId)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - AdminCreateRestaurantForUserSheet

struct AdminCreateRestaurantForUserSheet: View {
    let dataService: DataService
    let ownerUid: String
    let onCreated: (String) -> Void

    @State private var name = ""
    @State private var cuisineType = ""
    @State private var description = ""
    @State private var deliveryTime = "30-45 dk"
    @State private var minOrder = ""
    @State private var imageUrl = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !cuisineType.trimmingCharacters(in: .whitespaces).isEmpty
    }

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
                    HStack {
                        Text("Min. sipariş ₺")
                        TextField("0", text: $minOrder).keyboardType(.decimalPad)
                    }
                }
                Section("Görsel") {
                    TextField("Kapak görseli URL (opsiyonel)", text: $imageUrl)
                        .textInputAutocapitalization(.never)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Yeni Mağaza Oluştur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button(action: createAndAssign) {
                            Text("Oluştur & Ata").fontWeight(.semibold)
                        }
                        .disabled(!isValid)
                    }
                }
            }
        }
    }

    private func createAndAssign() {
        isLoading = true
        errorMessage = nil
        let newId = UUID().uuidString
        let restaurant = Restaurant(
            id: newId,
            name: name.trimmingCharacters(in: .whitespaces),
            ownerId: ownerUid,
            description: description,
            cuisineType: cuisineType.trimmingCharacters(in: .whitespaces),
            imageUrl: imageUrl.isEmpty ? nil : imageUrl,
            rating: 0,
            deliveryTime: deliveryTime.isEmpty ? "30-45 dk" : deliveryTime,
            minOrderAmount: Double(minOrder) ?? 0,
            menu: [],
            isActive: true
        )
        dataService.createRestaurantForOwner(restaurant: restaurant, ownerUid: ownerUid) { error in
            isLoading = false
            if let error {
                errorMessage = error.localizedDescription
            } else {
                onCreated(newId)
                dismiss()
            }
        }
    }
}
