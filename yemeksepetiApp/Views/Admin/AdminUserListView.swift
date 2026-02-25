import SwiftUI
import Combine

struct AdminUserListView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var adminVM: AdminViewModel

    // ── UI-only state ────────────────────────────────────────────────────────
    @State private var showingRoleSheet       = false
    @State private var activeUser: AppUser?
    @State private var showingRestaurantPicker = false
    @State private var availableRestaurants: [Restaurant] = []
    @State private var isLoadingRestaurants   = false
    @State private var alertTitle             = ""
    @State private var showingAlert           = false
    @State private var showingCreateUser      = false
    @State private var showingQuickAssign     = false
    @State private var showingDeleteAllConfirm = false
    @State private var isDeletingAll          = false
    @State private var showingCoOwnerPicker   = false
    @State private var showingCityFilter      = false
    /// id → Restaurant map for UserRow's storeOwner badge
    @State private var restaurantMap: [String: Restaurant] = [:]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            filterChipsRow
            Divider()
            errorBanner
            contentArea
        }
        .navigationTitle(adminVM.users.isEmpty
            ? "Kullanıcı Yönetimi"
            : "Kullanıcılar (\(adminVM.userTotal))")
        .toolbar { toolbarContent }
        .confirmationDialog(
            activeUser.map { "İşlem: \($0.email)" } ?? "Kullanıcı İşlemleri",
            isPresented: $showingRoleSheet,
            titleVisibility: .visible
        ) {
            if let user = activeUser {
                Button("Süper Admin Yap")   { performUpdateRole(uid: user.id, role: .superAdmin) }
                Button("Mağaza Sahibi Yap") { performUpdateRole(uid: user.id, role: .storeOwner) }
                Button("Ortak Sahip Yap") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showingCoOwnerPicker = true
                    }
                }
                Button("Normal Kullanıcı Yap") { performUpdateRole(uid: user.id, role: .user) }
                Button("Kullanıcıyı Sil", role: .destructive) { performDelete(uid: user.id) }
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
                if let user = activeUser { performAssignOwner(uid: user.id, restaurantId: restaurantId) }
                showingRestaurantPicker = false
            }
        }
        .sheet(isPresented: $showingCreateUser) {
            AdminCreateUserSheet(viewModel: viewModel) { adminVM.reloadUsers() }
        }
        .sheet(isPresented: $showingQuickAssign) {
            AdminQuickRoleAssignSheet(allUsers: adminVM.users) { uid, role in
                performUpdateRole(uid: uid, role: role)
            }
        }
        .sheet(isPresented: $showingCoOwnerPicker) {
            CoOwnerPickerSheet(
                restaurants: availableRestaurants,
                isLoading: isLoadingRestaurants,
                userEmail: activeUser?.email ?? ""
            ) { restaurantId in
                if let user = activeUser { performAssignCoOwner(uid: user.id, restaurantId: restaurantId) }
                showingCoOwnerPicker = false
            }
        }
        .confirmationDialog(
            "Tüm Kullanıcıları Sil",
            isPresented: $showingDeleteAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Evet, Hepsini Sil", role: .destructive) { performDeleteAll() }
            Button("İptal", role: .cancel) {}
        } message: {
            Text("Bu işlem geri alınamaz. \(adminVM.userTotal) kullanıcı silinecek.")
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("Tamam", role: .cancel) {}
        }
        .sheet(isPresented: $showingCityFilter) { cityFilterSheet }
        .onAppear {
            if adminVM.users.isEmpty { adminVM.reloadUsers() }
            loadRestaurantsIfNeeded()
        }
        .refreshable { adminVM.reloadUsers() }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.gray)
                TextField("Email veya isim ara...", text: $adminVM.userSearchQuery)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                if !adminVM.userSearchQuery.isEmpty {
                    Button {
                        adminVM.userSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            if adminVM.isLoadingUsers { ProgressView().padding(.trailing, 4) }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Filter chips

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let counts = adminVM.userRoleCounts
                FilterChip(label: "Tümü",
                           isActive: adminVM.userRoleFilter == nil, color: .gray) {
                    withAnimation(.easeInOut(duration: 0.2)) { adminVM.userRoleFilter = nil }
                }
                FilterChip(label: "Kullanıcı",
                           isActive: adminVM.userRoleFilter == .user,
                           color: .blue, count: counts.users) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        adminVM.userRoleFilter = adminVM.userRoleFilter == .user ? nil : .user
                    }
                }
                FilterChip(label: "Mağaza Sahibi",
                           isActive: adminVM.userRoleFilter == .storeOwner,
                           color: .orange, count: counts.storeOwners) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        adminVM.userRoleFilter = adminVM.userRoleFilter == .storeOwner ? nil : .storeOwner
                    }
                }
                FilterChip(label: "Yönetici",
                           isActive: adminVM.userRoleFilter == .superAdmin,
                           color: .purple, count: counts.admins) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        adminVM.userRoleFilter = adminVM.userRoleFilter == .superAdmin ? nil : .superAdmin
                    }
                }
                Divider().frame(height: 24)
                FilterChip(
                    label: adminVM.userCityFilter ?? "Şehir",
                    isActive: adminVM.userCityFilter != nil,
                    color: .green, icon: "mappin.circle.fill"
                ) { showingCityFilter = true }
                if adminVM.userRoleFilter != nil || adminVM.userCityFilter != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            adminVM.userRoleFilter = nil
                            adminVM.userCityFilter = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 6)
    }

    // MARK: - Error banner

    @ViewBuilder
    private var errorBanner: some View {
        if let err = adminVM.userError {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text(err).font(.caption).foregroundColor(.orange)
                Spacer()
                Button("Tekrar Dene") { adminVM.reloadUsers() }
                    .font(.caption).foregroundColor(.blue)
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
        }
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        let hasFilters = adminVM.userRoleFilter != nil
            || adminVM.userCityFilter != nil
            || !adminVM.userSearchQuery.isEmpty

        if adminVM.isLoadingUsers && adminVM.users.isEmpty {
            Spacer()
            ProgressView("Kullanıcılar yükleniyor...")
            Spacer()
        } else if adminVM.users.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: hasFilters ? "magnifyingglass" : "person.slash")
                    .font(.system(size: 44)).foregroundColor(.gray)
                Text(hasFilters ? "Arama sonucu bulunamadı" : "Henüz kullanıcı yok")
                    .foregroundColor(.secondary)
                if hasFilters {
                    Button("Filtreleri Temizle") {
                        adminVM.userRoleFilter  = nil
                        adminVM.userCityFilter  = nil
                        adminVM.userSearchQuery = ""
                    }
                    .font(.caption).foregroundColor(.orange)
                }
            }
            Spacer()
        } else {
            List {
                ForEach(adminVM.users) { user in
                    UserRow(
                        user: user,
                        restaurant: user.managedRestaurantId.flatMap { restaurantMap[$0] },
                        onEdit: { activeUser = user; showingRoleSheet = true }
                    )
                }
                // ── Infinite scroll footer ───────────────────────────────────
                if adminVM.hasMoreUsers {
                    HStack {
                        Spacer()
                        if adminVM.isLoadingUsers {
                            ProgressView().padding(.vertical, 8)
                        } else {
                            Text("Daha fazla yükle")
                                .font(.caption).foregroundColor(.secondary).padding(.vertical, 8)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture  { adminVM.loadMoreUsers() }
                    .onAppear      { adminVM.loadMoreUsers() }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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

    // MARK: - City filter sheet

    @ViewBuilder
    private var cityFilterSheet: some View {
        NavigationView {
            List {
                Button {
                    adminVM.userCityFilter = nil; showingCityFilter = false
                } label: {
                    HStack {
                        Text("Tüm Şehirler").foregroundColor(.primary)
                        Spacer()
                        if adminVM.userCityFilter == nil {
                            Image(systemName: "checkmark").foregroundColor(.orange)
                        }
                    }
                }
                ForEach(adminVM.userDistinctCities, id: \.self) { city in
                    Button {
                        adminVM.userCityFilter = city; showingCityFilter = false
                    } label: {
                        HStack {
                            Text(city).foregroundColor(.primary)
                            Spacer()
                            if adminVM.userCityFilter == city {
                                Image(systemName: "checkmark").foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Şehir Filtresi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { showingCityFilter = false }
                }
            }
        }
        .if_iOS16_presentationDetents()
    }

    // MARK: - Actions

    private func loadRestaurantsIfNeeded() {
        guard availableRestaurants.isEmpty else { return }
        isLoadingRestaurants = true
        viewModel.dataService.getAllRestaurantsForAdmin { restaurants in
            restaurantMap = Dictionary(uniqueKeysWithValues: restaurants.map { ($0.id, $0) })
            availableRestaurants = restaurants
            isLoadingRestaurants = false
        }
    }

    private func performUpdateRole(uid: String, role: UserRole) {
        Task {
            do {
                try await adminVM.performUpdateUserRole(uid: uid, role: role)
                await MainActor.run {
                    alertTitle  = "Rol başarıyla güncellendi."
                    showingAlert = true
                }
            } catch {
                await MainActor.run {
                    alertTitle  = "Hata: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }

    private func performDelete(uid: String) {
        Task {
            do {
                try await adminVM.performDeleteUser(uid: uid)
                await MainActor.run {
                    alertTitle  = "Kullanıcı silindi."
                    showingAlert = true
                }
            } catch {
                await MainActor.run {
                    alertTitle  = "Silme hatası: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }

    private func performAssignOwner(uid: String, restaurantId: String) {
        viewModel.dataService.assignStoreOwner(uid: uid, restaurantId: restaurantId) { error in
            if let error {
                alertTitle = "Hata: \(error.localizedDescription)"
            } else {
                alertTitle = "Mağaza sahibi başarıyla atandı."
                adminVM.reloadUsers()
            }
            showingAlert = true
        }
    }

    private func performAssignCoOwner(uid: String, restaurantId: String) {
        Task {
            do {
                try await adminVM.performAssignManagedRestaurant(uid: uid, restaurantId: restaurantId)
                await MainActor.run {
                    alertTitle  = "Ortak sahip başarıyla atandı."
                    showingAlert = true
                }
            } catch {
                await MainActor.run {
                    alertTitle  = "Hata: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }

    private func performDeleteAll() {
        isDeletingAll = true
        let currentUid = viewModel.authService.currentUser?.id
        let usersToDelete = adminVM.users.filter { $0.id != currentUid }
        let group = DispatchGroup()
        var errorCount = 0
        for user in usersToDelete {
            group.enter()
            viewModel.deleteUser(uid: user.id) { error in
                if error != nil { errorCount += 1 }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            isDeletingAll = false
            let deleted = usersToDelete.count - errorCount
            alertTitle = errorCount == 0
                ? "\(deleted) kullanıcı silindi."
                : "\(deleted) silindi, \(errorCount) hata."
            showingAlert = true
            adminVM.reloadUsers()
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
    var restaurant: Restaurant? = nil
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // ── Rol ikonu (avatar)
            ZStack {
                Circle()
                    .fill(roleColor(user.role).opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: iconForRole(user.role))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(roleColor(user.role))
            }

            // ── İçerik
            VStack(alignment: .leading, spacing: 3) {
                // Ad (varsa) + e-posta
                if let name = user.fullName, !name.isEmpty {
                    Text(name)
                        .font(.subheadline).fontWeight(.semibold)
                    Text(user.email)
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text(user.email)
                        .font(.subheadline).fontWeight(.semibold)
                }

                // Rol etiketi
                HStack(spacing: 4) {
                    Text(roleLabel(user.role))
                        .font(.caption2).fontWeight(.medium)
                        .foregroundColor(roleColor(user.role))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(roleColor(user.role).opacity(0.1))
                        .clipShape(Capsule())

                    // ── Mağaza rozeti (yalnızca storeOwner)
                    if user.role == .storeOwner, let r = restaurant {
                        restaurantBadge(r)
                    } else if user.role == .storeOwner, user.managedRestaurantId != nil {
                        // Restoran haritasında henüz yüklenmemiş
                        Label("Mağaza yükleniyor…", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    // ── Mağaza rozeti: ad + disambiguator + kısa ID  ─────────────────────────
    @ViewBuilder
    private func restaurantBadge(_ r: Restaurant) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "storefront.fill")
                .font(.caption2)
            // İsim
            Text(r.name)
                .font(.caption2).fontWeight(.medium)
                .lineLimit(1)
            // Şehir (belirsizliği gider; aynı şehirdeyse mutfak türü eklenir)
            if let city = r.city, !city.isEmpty {
                Text("· \(city)")
                    .font(.caption2).foregroundColor(.secondary)
            }
            // Mutfak türü (ikinci belirsizlik giderici)
            if !r.cuisineType.isEmpty {
                Text("· \(r.cuisineType)")
                    .font(.caption2).foregroundColor(.secondary)
            }
            // Kısa ID (mutlak tekil tanımlayıcı — son 5 kr)
            Text("#\(r.id.suffix(5))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color.orange.opacity(0.1))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.orange.opacity(0.25), lineWidth: 0.5))
    }

    func iconForRole(_ role: UserRole) -> String {
        switch role {
        case .superAdmin: return "shield.fill"
        case .storeOwner: return "storefront.fill"
        case .user:       return "person.fill"
        }
    }

    func roleLabel(_ role: UserRole) -> String {
        switch role {
        case .superAdmin: return "Yönetici"
        case .storeOwner: return "Mağaza Sahibi"
        case .user:       return "Kullanıcı"
        }
    }

    func roleColor(_ role: UserRole) -> Color {
        switch role {
        case .superAdmin: return .purple
        case .storeOwner: return .orange
        case .user:       return .blue
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

// MARK: - CoOwnerPickerSheet

/// Mevcut bir restoranı seçerek kullanıcıyı ortak sahip yapar.
struct CoOwnerPickerSheet: View {
    let restaurants: [Restaurant]
    let isLoading: Bool
    let userEmail: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Restoranlar yükleniyor...")
                } else if restaurants.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "building.2.slash").font(.system(size: 40)).foregroundColor(.gray)
                        Text("Henüz mağaza yok").foregroundColor(.secondary)
                    }
                } else {
                    List(restaurants) { restaurant in
                        Button {
                            onSelect(restaurant.id)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(restaurant.name).fontWeight(.semibold).foregroundColor(.primary)
                                HStack(spacing: 6) {
                                    if let city = restaurant.city {
                                        Text(city).font(.caption).foregroundColor(.secondary)
                                        Text("·").font(.caption).foregroundColor(.secondary)
                                    }
                                    Text(restaurant.cuisineType).font(.caption).foregroundColor(.secondary)
                                    if !restaurant.isActive {
                                        Text("· Pasif").font(.caption).foregroundColor(.red)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Mağaza Seç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    Text("\(userEmail) kullanıcısını ortak sahip yapacaksınız.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    Divider()
                }
                .background(Color(.systemGroupedBackground))
            }
        }
    }
}
