import SwiftUI

struct AdminUserListView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var searchQuery = ""
    @State private var allUsers: [AppUser] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingRoleSheet = false
    @State private var activeUser: AppUser?
    @State private var showingRestaurantPicker = false
    @State private var availableRestaurants: [Restaurant] = []
    @State private var isLoadingRestaurants = false
    @State private var alertTitle = ""
    @State private var showingAlert = false
    @State private var showingCreateUser = false
    @State private var showingQuickAssign = false      // ← Email ile yetki ata
    @State private var showingDeleteAllConfirm = false // ← Tüm kullanıcıları sil
    @State private var isDeletingAll = false

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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingQuickAssign = true
                    } label: {
                        Label("Email ile Yetki Ata", systemImage: "person.badge.shield.checkmark")
                    }
                    Button {
                        showingCreateUser = true
                    } label: {
                        Label("Yeni Kullanıcı Oluştur", systemImage: "person.badge.plus")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showingDeleteAllConfirm = true
                    } label: {
                        Label("Tüm Kullanıcıları Sil", systemImage: "trash.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
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
        // ── Yeni kullanıcı oluşturma sayfası ────────────────────────────────
        .sheet(isPresented: $showingCreateUser) {
            AdminCreateUserSheet(viewModel: viewModel) {
                loadAllUsers()
            }
        }
        // ── Email ile hızlı yetki ata ─────────────────────────────────────────
        .sheet(isPresented: $showingQuickAssign) {
            AdminQuickRoleAssignSheet(allUsers: allUsers) { uid, role in
                updateUserRole(uid: uid, role: role)
            }
        }
        // ── Tüm kullanıcıları sil onayı ──────────────────────────────────────
        .confirmationDialog(
            "Tüm Kullanıcıları Sil",
            isPresented: $showingDeleteAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Evet, Hepsini Sil", role: .destructive) { deleteAllUsers() }
            Button("İptal", role: .cancel) {}
        } message: {
            Text("Bu işlem geri alınamaz. \(allUsers.count) kullanıcı silinecek.")
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
        viewModel.fetchAllUsers { users, error in
            isLoading = false
            if let error { errorMessage = error }
            allUsers = users
        }
    }

    func updateUserRole(uid: String, role: UserRole) {
        viewModel.updateUserRole(uid: uid, role: role) { error in
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
        activeUser = user
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
        viewModel.deleteUser(uid: uid) { error in
            if let error {
                alertTitle = "Silme hatası: \(error.localizedDescription)"
            } else {
                alertTitle = "Kullanıcı silindi."
                loadAllUsers()
            }
            showingAlert = true
        }
    }

    func deleteAllUsers() {
        isDeletingAll = true
        let usersToDelete = allUsers
        let group = DispatchGroup()
        var errors: [String] = []
        for user in usersToDelete {
            group.enter()
            viewModel.deleteUser(uid: user.id) { error in
                if let error { errors.append(error.localizedDescription) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            isDeletingAll = false
            if errors.isEmpty {
                alertTitle = "\(usersToDelete.count) kullanıcı silindi."
            } else {
                alertTitle = "\(usersToDelete.count - errors.count) silindi, \(errors.count) hata."
            }
            showingAlert = true
            loadAllUsers()
        }
    }
}

// MARK: - AdminQuickRoleAssignSheet

struct AdminQuickRoleAssignSheet: View {
    let allUsers: [AppUser]
    let onAssign: (String, UserRole) -> Void

    @State private var emailQuery = ""
    @State private var selectedRole: UserRole = .user
    @State private var selectedUser: AppUser?
    @Environment(\.dismiss) private var dismiss

    private var matchedUser: AppUser? {
        let q = emailQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return nil }
        return allUsers.first { $0.email.lowercased() == q }
    }

    private var suggestions: [AppUser] {
        let q = emailQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2 else { return [] }
        return allUsers.filter { $0.email.lowercased().contains(q) }.prefix(5).map { $0 }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Kullanıcı E-postası")) {
                    TextField("ornek@mail.com", text: $emailQuery)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .disableAutocorrection(true)
                        .onChange(of: emailQuery) { _ in selectedUser = nil }

                    if !suggestions.isEmpty && selectedUser == nil {
                        ForEach(suggestions) { user in
                            Button {
                                emailQuery = user.email
                                selectedUser = user
                            } label: {
                                HStack {
                                    Image(systemName: iconForRole(user.role))
                                        .foregroundColor(.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.email).foregroundColor(.primary)
                                        Text(user.role.rawValue)
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                if let user = selectedUser ?? matchedUser {
                    Section(header: Text("Seçilen Kullanıcı")) {
                        HStack {
                            Image(systemName: iconForRole(user.role))
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.email).fontWeight(.semibold)
                                Text("Mevcut rol: \(user.role.rawValue)")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section(header: Text("Yeni Rol")) {
                        Picker("Rol", selection: $selectedRole) {
                            Text("Kullanıcı").tag(UserRole.user)
                            Text("Mağaza Sahibi").tag(UserRole.storeOwner)
                            Text("Süper Admin").tag(UserRole.superAdmin)
                        }
                        .pickerStyle(.segmented)

                        Button {
                            onAssign(user.id, selectedRole)
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Yetkiyi Uygula")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .background(Color.orange)
                            .cornerRadius(10)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                } else if emailQuery.count >= 2 && matchedUser == nil && suggestions.isEmpty {
                    Section {
                        HStack {
                            Image(systemName: "person.fill.questionmark")
                                .foregroundColor(.secondary)
                            Text("Bu e-posta ile kullanıcı bulunamadı")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Email ile Yetki Ata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
            }
            .onAppear { selectedRole = .user }
        }
    }

    func iconForRole(_ role: UserRole) -> String {
        switch role {
        case .superAdmin: return "shield.fill"
        case .storeOwner: return "briefcase.fill"
        case .user:       return "person.fill"
        }
    }
}

// MARK: - AdminCreateUserSheet

struct AdminCreateUserSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let onCreated: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var selectedRole: UserRole = .user
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 6
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Kullanıcı Bilgileri") {
                    TextField("E-posta *", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .disableAutocorrection(true)
                    SecureField("Şifre * (min 6 karakter)", text: $password)
                    TextField("Ad Soyad (opsiyonel)", text: $displayName)
                }

                Section("Rol") {
                    Picker("Rol", selection: $selectedRole) {
                        Text("Kullanıcı").tag(UserRole.user)
                        Text("Mağaza Sahibi").tag(UserRole.storeOwner)
                        Text("Süper Admin").tag(UserRole.superAdmin)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Yeni Kullanıcı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Oluştur") { createUser() }
                            .font(Font.body.weight(.semibold))
                            .disabled(!isValid)
                    }
                }
            }
        }
    }

    private func createUser() {
        guard isValid else { return }
        isLoading = true
        errorMessage = nil
        let dn = displayName.trimmingCharacters(in: .whitespaces)
        viewModel.createUser(
            email: email.trimmingCharacters(in: .whitespaces),
            password: password,
            displayName: dn.isEmpty ? nil : dn,
            role: selectedRole
        ) { _, error in
            isLoading = false
            if let error {
                errorMessage = error.localizedDescription
            } else {
                onCreated()
                dismiss()
            }
        }
    }
}

// MARK: - UserRow

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
        case .user:       return "person.fill"
        }
    }
}

// MARK: - RestaurantPickerView

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
                                                    Text("Sahip: \(ownerId.prefix(12))…")
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
