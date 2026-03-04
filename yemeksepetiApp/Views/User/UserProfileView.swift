import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - UserProfileView

struct UserProfileView: View {
    @ObservedObject var viewModel: AppViewModel
    private var user: AppUser? { viewModel.authService.currentUser }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ProfileHeaderView(user: user)

                VStack(spacing: 12) {

                    // ── Hesap ───────────────────────────────────────────────
                    ProfileSection(title: "HESAP") {
                        ProfileNavRow(icon: "bag.fill", title: "Siparişlerim", color: .orange) {
                            UserOrdersView(viewModel: viewModel)
                        }
                        ProfileDivider()
                        ProfileNavRow(icon: "person.fill", title: "Kullanıcı Bilgileri", color: .blue) {
                            UserInfoEditView(viewModel: viewModel)
                        }
                        ProfileDivider()
                        ProfileNavRow(icon: "mappin.and.ellipse", title: "Adreslerim", color: .red) {
                            UserAddressesView(viewModel: viewModel)
                        }
                        ProfileDivider()
                        ProfileNavRow(icon: "creditcard.fill", title: "Kayıtlı Kartlarım", color: .green) {
                            UserCardsView(viewModel: viewModel)
                        }
                        ProfileDivider()
                        ProfileNavRow(icon: "tag.fill", title: "İndirim Kuponlarım", color: .orange) {
                            UserCouponsView(viewModel: viewModel)
                        }
                    }

                    // ── Tercihler ───────────────────────────────────────────
                    ProfileSection(title: "TERCİHLER") {
                        ProfileNavRow(icon: "envelope.fill", title: "E-posta Değişikliği", color: .purple) {
                            EmailChangeView(viewModel: viewModel)
                        }
                        ProfileDivider()
                        ProfileNavRow(icon: "bell.fill", title: "Duyuru Tercihleri", color: .yellow) {
                            NotificationPrefsView(viewModel: viewModel)
                        }
                    }

                    // ── Güvenlik ────────────────────────────────────────────
                    ProfileSection(title: "GÜVENLİK") {
                        ProfileNavRow(icon: "lock.fill", title: "Şifre Değiştir", color: .indigo) {
                            ChangePasswordView(viewModel: viewModel)
                        }
                        ProfileDivider()
                        ProfileNavRow(icon: "lock.shield.fill", title: "Giriş Bilgileri & Oturumlar", color: .teal) {
                            LoginHistoryView(viewModel: viewModel)
                        }
                    }

                    // ── Daha Fazla ──────────────────────────────────────────
                    ProfileSection(title: "DAHA FAZLA") {
                        ProfileNavRow(icon: "questionmark.circle.fill", title: "Yardım & Destek", color: .gray) {
                            HelpSupportView()
                        }
                        ProfileDivider()
                        ProfileNavRow(icon: "hand.raised.fill", title: "Gizlilik Politikası", color: Color(.systemGray)) {
                            PrivacyPolicyView()
                        }
                        ProfileDivider()
                        ProfileNavRow(icon: "info.circle.fill", title: "Hakkında", color: Color(.systemGray2)) {
                            AboutAppView()
                        }
                    }

                    // ── Çıkış ───────────────────────────────────────────────
                    Button { viewModel.authService.signOut() } label: {
                        HStack {
                            Spacer()
                            Label("Çıkış Yap", systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.headline).foregroundColor(.white)
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.red)
                        .cornerRadius(14)
                    }
                    .buttonStyle(PressScaleButtonStyle(pressedScale: 0.985))

                    Text("Yemeksepeti v1.0.0")
                        .font(.caption2).foregroundColor(Color(.tertiaryLabel))
                        .padding(.bottom, 24)
                }
                .padding(.horizontal).padding(.top, 16)
                .animation(AppMotion.standard, value: user?.id ?? "")
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Hesabım")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Header

private struct ProfileHeaderView: View {
    let user: AppUser?
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.orange, .red],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                Text(String((user?.fullName ?? user?.email ?? "?").prefix(1)).uppercased())
                    .font(.system(size: 36, weight: .bold)).foregroundColor(.white)
            }
            .padding(.top, 24)

            Text(user?.fullName?.isEmpty == false ? user!.fullName! : "İsim belirtilmedi")
                .font(.title3).fontWeight(.bold)
            Text(user?.email ?? "").font(.subheadline).foregroundColor(.secondary)

            if let city = user?.city, !city.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill").foregroundColor(.red).font(.caption)
                    Text(city).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 20)
        .background(Color(.systemBackground))
    }
}

// MARK: - Section & Row helpers

private struct ProfileSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                .padding(.leading, 2)
            VStack(spacing: 0) {
                content()
            }
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
            .subtleCardTransition()
        }
    }
}

private struct ProfileNavRow<Dest: View>: View {
    let icon: String; let title: String; let color: Color
    @ViewBuilder let destination: () -> Dest
    var body: some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(color).frame(width: 34, height: 34)
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                }
                Text(title).foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .buttonStyle(PressScaleButtonStyle(pressedScale: 0.985))
    }
}

private struct ProfileDivider: View {
    var body: some View {
        Divider().padding(.leading, 62)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Kullanıcı Bilgileri
// ═══════════════════════════════════════════════════════════════════

struct UserInfoEditView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var fullName = ""
    @State private var phone = ""
    @State private var city = ""
    @State private var showingCityPicker = false
    @State private var isSaving = false
    @State private var message: String?
    @State private var isSuccess = false

    var body: some View {
        Form {
            Section("Ad Soyad") {
                TextField("Ad Soyad", text: $fullName)
            }
            Section("İletişim") {
                TextField("Telefon numarası", text: $phone).keyboardType(.phonePad)
                HStack {
                    Text("E-posta")
                    Spacer()
                    Text(viewModel.authService.currentUser?.email ?? "")
                        .foregroundColor(.secondary)
                }
            }
            Section("Şehir") {
                Button { showingCityPicker = true } label: {
                    HStack {
                        Text("Şehir")
                        Spacer()
                        Text(city.isEmpty ? "Seçiniz" : city)
                            .foregroundColor(city.isEmpty ? .secondary : .primary)
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.primary)
            }
            if let msg = message {
                Section {
                    Text(msg).foregroundColor(isSuccess ? .green : .red).font(.caption)
                }
            }
            Section {
                Button { save() } label: {
                    if isSaving { ProgressView() } else {
                        Text("Kaydet").frame(maxWidth: .infinity).foregroundColor(.white)
                            .padding(8).background(Color.orange).cornerRadius(10)
                    }
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("Kullanıcı Bilgileri")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { prefill() }
        .sheet(isPresented: $showingCityPicker) {
            CityPickerSheet(selectedCity: $city)
        }
    }

    private func prefill() {
        fullName = viewModel.authService.currentUser?.fullName ?? ""
        phone    = viewModel.authService.currentUser?.phone ?? ""
        city     = viewModel.authService.currentUser?.city ?? ""
    }

    private func save() {
        guard let uid = viewModel.authService.currentUser?.id else { return }
        isSaving = true; message = nil
        viewModel.dataService.updateUserProfile(uid: uid, data: [
            "fullName": fullName, "phone": phone, "city": city
        ]) { error in
            isSaving = false
            if let error { message = error.localizedDescription; isSuccess = false }
            else { message = "Bilgiler güncellendi ✓"; isSuccess = true; viewModel.authService.refreshCurrentUser() }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Adreslerim
// ═══════════════════════════════════════════════════════════════════

struct UserAddressesView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var addresses: [UserAddress] = []
    @State private var isLoading = true
    @State private var showingAdd = false
    @State private var editingAddress: UserAddress?

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if addresses.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "mappin.slash").font(.system(size: 44)).foregroundColor(.gray)
                    Text("Kayıtlı adres yok").foregroundColor(.secondary)
                    Button("Adres Ekle") { showingAdd = true }
                        .buttonStyle(.borderedProminent).tint(.orange)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(addresses) { addr in
                        AddressRow(
                            address: addr,
                            onEdit:   { editingAddress = addr },
                            onDelete: { delete(addr) }
                        )
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Adreslerim")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .onAppear { fetch() }
        .sheet(isPresented: $showingAdd, onDismiss: { fetch() }) {
            AddAddressView(viewModel: viewModel)
        }
        .sheet(item: $editingAddress, onDismiss: { fetch() }) { addr in
            AddAddressView(viewModel: viewModel, existingAddress: addr)
        }
    }

    private func fetch() {
        guard let uid = viewModel.authService.currentUser?.id else { isLoading = false; return }
        isLoading = true
        viewModel.dataService.fetchAddresses(uid: uid) { result in
            addresses = result; isLoading = false
        }
    }

    private func delete(_ address: UserAddress) {
        guard let uid = viewModel.authService.currentUser?.id else { return }
        viewModel.dataService.deleteAddress(uid: uid, addressId: address.id) { _ in
            addresses.removeAll { $0.id == address.id }
        }
    }
}

private struct AddressRow: View {
    let address: UserAddress
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: address.title == "Ev" ? "house.fill" :
                          address.title == "İş" ? "briefcase.fill" : "mappin.fill")
                        .foregroundColor(.orange).font(.caption)
                    Text(address.title).fontWeight(.semibold)
                    if address.isDefault {
                        Text("Varsayılan").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.15)).foregroundColor(.green).cornerRadius(4)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                Button { onDelete() } label: {
                    Image(systemName: "trash").foregroundColor(.red).font(.caption)
                }
                .buttonStyle(.borderless)
                .padding(.leading, 6)
            }
            Text(address.fullAddress).font(.caption).foregroundColor(.secondary).lineLimit(2)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
    }
}

// MARK: - LocationManager

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var authStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authStatus = manager.authorizationStatus
    }

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default: break
        }
    }

    func startUpdating() { manager.startUpdatingLocation() }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        DispatchQueue.main.async { self.authStatus = m.authorizationStatus }
        if m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways {
            m.startUpdatingLocation()
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let loc = locs.last, loc.horizontalAccuracy < 100 else { return }
        DispatchQueue.main.async {
            self.location = loc
            m.stopUpdatingLocation()
        }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        print("[LocationManager] \(error.localizedDescription)")
    }
}

// MARK: - AddAddressView

struct AddAddressView: View {
    @ObservedObject var viewModel: AppViewModel
    var existingAddress: UserAddress? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationManager = LocationManager()

    // ── Step tracking ────────────────────────────────────────────────
    @State private var step: Int = 1

    // ── Map ──────────────────────────────────────────────────────────
    @State private var region: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9208, longitude: 32.8541),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var pinCoordinate = CLLocationCoordinate2D(latitude: 39.9208, longitude: 32.8541)
    @State private var isGeocoding = false
    @State private var geocodeError: String?
    @State private var hasFlownToUserLocation = false

    // ── Search ───────────────────────────────────────────────────────
    @State private var searchQuery = ""
    @State private var searchResults: [MKMapItem] = []
    @FocusState private var searchFocused: Bool
    @State private var searchTask: Task<Void, Never>?
    /// Placemark from the last MKLocalSearch selection.
    /// Used as a higher-fidelity source for neighbourhood data
    /// compared to CLGeocoder's reverse-geocode result.
    @State private var searchHintPlacemark: MKPlacemark? = nil

    // ── Address fields ───────────────────────────────────────────────
    @State private var labelTitle   = "Ev"
    @State private var city         = ""
    @State private var district     = ""
    @State private var neighborhood = ""
    @State private var street       = ""
    @State private var buildingNo   = ""
    @State private var flatNo       = ""
    @State private var directions   = ""
    @State private var phone        = ""
    @State private var isDefault    = false
    @State private var isSaving     = false

    let labels = ["Ev", "İş", "Okul", "Diğer"]
    private var isValid: Bool { !city.isEmpty && !district.isEmpty && !street.isEmpty }

    var body: some View {
        NavigationView {
            ZStack {
                if step == 1 {
                    mapStep
                        .transition(.asymmetric(insertion: .identity, removal: .move(edge: .leading)))
                } else {
                    detailStep
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .identity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: step)
            .navigationTitle(step == 1 ? "Konum Seç" : "Adres Detayları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == 1 ? "İptal" : "Geri") {
                        if step == 1 { dismiss() } else { withAnimation { step = 1 } }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if step == 2 {
                        if isSaving { ProgressView() }
                        else { Button("Kaydet") { save() }.disabled(!isValid) }
                    }
                }
            }
        }
        .onAppear {
            if let addr = existingAddress {
                labelTitle   = addr.title
                city         = addr.city
                district     = addr.district
                neighborhood = addr.neighborhood
                street       = addr.street
                buildingNo   = addr.buildingNo
                flatNo       = addr.flatNo
                directions   = addr.directions
                phone        = addr.phone
                isDefault    = addr.isDefault
                // Restore saved pin so coordinates are correct even if user
                // skips the map step
                if let lat = addr.latitude, let lon = addr.longitude {
                    pinCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
                step = 2
            } else {
                locationManager.requestPermission()
                fallbackToSavedCity()
            }
        }
        .onChange(of: locationManager.location) { loc in
            guard let loc, !hasFlownToUserLocation else { return }
            hasFlownToUserLocation = true
            let coord = loc.coordinate
            pinCoordinate = coord
            withAnimation(.easeInOut(duration: 0.8)) {
                region = MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
                )
            }
        }
    }

    // MARK: - Step 1: Map

    private var mapStep: some View {
        ZStack(alignment: .bottom) {
            // Full-screen interactive map with pin pinned to its center
            Map(coordinateRegion: $region)
                .ignoresSafeArea(edges: .bottom)
                .onTapGesture {
                    searchFocused = false
                    withAnimation { searchResults = [] }
                }
                // ── Fixed center pin overlaid directly on the map ──────
                .overlay(alignment: .center) {
                    VStack(spacing: 0) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 44))
                            .symbolRenderingMode(.multicolor)
                            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                        // Small dot so the exact tap point is clear
                        Circle()
                            .fill(Color.red.opacity(0.35))
                            .frame(width: 8, height: 8)
                    }
                    .allowsHitTesting(false)
                }

            // ── Search + results (top overlay) ────────────────────────
            VStack(spacing: 0) {
                searchBarView
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                if !searchResults.isEmpty {
                    searchResultsView
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()
            }
            .animation(.easeInOut(duration: 0.2), value: searchResults.isEmpty)

            // ── Bottom card ───────────────────────────────────────────
            VStack(spacing: 8) {

                // Locate-me button (above card, trailing)
                HStack {
                    Spacer()
                    Button { flyToUserLocation() } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(locationManager.authStatus == .denied ? .gray : .orange)
                            .padding(12)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                    }
                    .padding(.trailing, 4)
                }

                // Card
                VStack(spacing: 12) {
                    VStack(spacing: 5) {
                        Text("Konumunuzu Belirleyin")
                            .font(.headline).fontWeight(.bold)
                        Text("Haritayı kaydırın veya arama yapın, pini doğru noktaya getirin")
                            .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                    }

                    if let error = geocodeError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        pinCoordinate = region.center
                        reverseGeocode(pinCoordinate)
                    } label: {
                        HStack(spacing: 8) {
                            if isGeocoding {
                                ProgressView().tint(.white)
                                Text("Adres alınıyor...").foregroundColor(.white)
                            } else {
                                Image(systemName: "location.circle.fill")
                                Text("Bu Konumu Seç")
                            }
                        }
                        .font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isGeocoding ? Color.gray : Color.orange)
                        .cornerRadius(14)
                    }
                    .disabled(isGeocoding)
                }
                .padding(20)
                .background(
                    Color(.systemBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 16, y: -4)
                )
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Search bar & results

    private var searchBarView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(searchFocused ? .orange : .secondary)
                .font(.system(size: 15, weight: .medium))
            TextField("Mahalle, sokak veya yer adı ara...", text: $searchQuery)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .onChange(of: searchQuery) { q in
                    searchTask?.cancel()
                    guard !q.trimmingCharacters(in: .whitespaces).isEmpty else {
                        searchResults = []; return
                    }
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 380_000_000)
                        guard !Task.isCancelled else { return }
                        await MainActor.run { performSearch(q) }
                    }
                }
                .onSubmit { performSearch(searchQuery) }
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchResults = []
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.regularMaterial)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    private var searchResultsView: some View {
        VStack(spacing: 0) {
            ForEach(Array(searchResults.prefix(5).enumerated()), id: \.offset) { idx, item in
                Button { selectSearchResult(item) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.orange)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name ?? "")
                                .font(.subheadline).foregroundColor(.primary).lineLimit(1)
                            let pm = item.placemark
                            Text(
                                [pm.thoroughfare,
                                 pm.locality,
                                 pm.administrativeArea]
                                    .compactMap { $0 }.joined(separator: ", ")
                            )
                            .font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.left").font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if idx < min(searchResults.count, 5) - 1 {
                    Divider().padding(.leading, 46)
                }
            }
        }
        .background(.regularMaterial)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }

    // MARK: - Step 2: Detail form

    private var detailStep: some View {
        ScrollView {
            VStack(spacing: 16) {

                // ── Map thumbnail ─────────────────────────────────────
                ZStack(alignment: .center) {
                    Map(coordinateRegion: .constant(MKCoordinateRegion(
                        center: pinCoordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                    )))
                    .frame(height: 140)
                    .cornerRadius(16)
                    .allowsHitTesting(false)

                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 36))
                        .symbolRenderingMode(.multicolor)
                        .shadow(radius: 3)

                    VStack {
                        HStack {
                            Spacer()
                            Button { withAnimation { step = 1 } } label: {
                                Label("Değiştir", systemImage: "arrow.uturn.left")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(8)
                            }
                            .padding(10)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal)

                // ── Label picker ──────────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {
                    Label("Adres Etiketi", systemImage: "tag.fill")
                        .font(.caption.weight(.semibold)).foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        ForEach(labels, id: \.self) { lbl in
                            Button { labelTitle = lbl } label: {
                                Text(lbl)
                                    .font(.subheadline.weight(labelTitle == lbl ? .semibold : .regular))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(labelTitle == lbl ? Color.orange : Color(.systemGray6))
                                    .foregroundColor(labelTitle == lbl ? .white : .primary)
                                    .cornerRadius(20)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // ── Auto-filled location fields ───────────────────────
                formCard(title: "Konum", icon: "mappin") {
                    modernField(label: "İl *", text: $city, placeholder: "Otomatik doldu")
                    Divider().padding(.leading, 16)
                    modernField(label: "İlçe *", text: $district, placeholder: "Otomatik doldu")
                    Divider().padding(.leading, 16)
                    modernField(label: "Mahalle", text: $neighborhood, placeholder: "Opsiyonel")
                }

                formCard(title: "Adres", icon: "house") {
                    modernField(label: "Sokak / Cadde *", text: $street, placeholder: "Otomatik doldu")
                    Divider().padding(.leading, 16)
                    HStack(spacing: 0) {
                        modernField(label: "Bina No", text: $buildingNo, placeholder: "-")
                            .frame(maxWidth: .infinity)
                        Divider().frame(height: 44)
                        modernField(label: "Daire No", text: $flatNo, placeholder: "-")
                            .frame(maxWidth: .infinity)
                    }
                    Divider().padding(.leading, 16)
                    modernField(label: "Kapı tarifi", text: $directions,
                                placeholder: "Ör: 3. kat, sol kapı", axis: .vertical)
                }

                formCard(title: "İletişim", icon: "phone.fill") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cep Telefonu").font(.caption2).foregroundColor(.orange)
                            .padding(.horizontal, 16).padding(.top, 10)
                        TextField("0 5xx xxx xx xx", text: $phone)
                            .font(.subheadline)
                            .keyboardType(.phonePad)
                            .padding(.horizontal, 16).padding(.bottom, 10)
                    }
                }

                formCard(title: "Ayarlar", icon: "gearshape") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Varsayılan adres").font(.subheadline)
                            Text("Siparişlerde önce bu adres gösterilir")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $isDefault).tint(.orange)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }

                Button { save() } label: {
                    HStack {
                        if isSaving { ProgressView().tint(.white) }
                        Text(isSaving ? "Kaydediliyor..." : "Adresi Kaydet")
                            .font(.headline).foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(isValid ? Color.orange : Color.gray)
                    .cornerRadius(14)
                }
                .disabled(!isValid || isSaving)
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .padding(.top, 16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - Form helpers

    private func formCard<C: View>(title: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption).foregroundColor(.orange)
                Text(title).font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
            content()
            Color.clear.frame(height: 4)
        }
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        .padding(.horizontal)
    }

    private func modernField(label: String, text: Binding<String>,
                             placeholder: String, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.orange)
                .padding(.horizontal, 16).padding(.top, 10)
            if axis == .vertical {
                ZStack(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder)
                            .font(.subheadline)
                            .foregroundColor(Color(.placeholderText))
                            .padding(.top, 8).padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: text)
                        .font(.subheadline)
                        .frame(minHeight: 70)
                }
                .padding(.horizontal, 16).padding(.bottom, 10)
            } else {
                TextField(placeholder, text: text)
                    .font(.subheadline)
                    .padding(.horizontal, 16).padding(.bottom, 10)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Location helpers

    private func flyToUserLocation() {
        if let loc = locationManager.location {
            pinCoordinate = loc.coordinate
            withAnimation(.easeInOut(duration: 0.6)) {
                region = MKCoordinateRegion(
                    center: loc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
                )
            }
        } else {
            locationManager.requestPermission()
            locationManager.startUpdating()
        }
    }

    private func fallbackToSavedCity() {
        guard let savedCity = viewModel.authService.currentUser?.city, !savedCity.isEmpty else { return }
        CLGeocoder().geocodeAddressString(savedCity + ", Türkiye") { placemarks, _ in
            guard !hasFlownToUserLocation, let loc = placemarks?.first?.location else { return }
            DispatchQueue.main.async {
                region = MKCoordinateRegion(
                    center: loc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
                pinCoordinate = loc.coordinate
            }
        }
    }

    // MARK: - Search

    private func performSearch(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { searchResults = []; return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        request.resultTypes = [.address, .pointOfInterest]
        // Bias results toward the current map region
        request.region = region
        MKLocalSearch(request: request).start { response, _ in
            DispatchQueue.main.async {
                self.searchResults = response?.mapItems ?? []
            }
        }
    }

    private func selectSearchResult(_ item: MKMapItem) {
        let coord = item.placemark.coordinate
        searchQuery = item.name ?? ""
        searchFocused = false
        withAnimation { searchResults = [] }
        // Save the forward-search placemark as a neighbourhood hint.
        // MKLocalSearch resolves "Akbilek Mahallesi" → subLocality = "Akbilek"
        // much more accurately than CLGeocoder reverse-geocoding the coordinate.
        searchHintPlacemark = item.placemark
        // Set pin and fly camera to the selected result.
        pinCoordinate = coord
        withAnimation(.easeInOut(duration: 0.6)) {
            region = MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
            )
        }
    }

    // MARK: - Reverse geocode

    private func reverseGeocode(_ coord: CLLocationCoordinate2D) {
        isGeocoding = true; geocodeError = nil
        // Consume the search hint now so a later manual pin drag won't
        // inherit stale neighbourhood data from a previous search selection.
        let hint = searchHintPlacemark
        searchHintPlacemark = nil

        CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: coord.latitude, longitude: coord.longitude),
            preferredLocale: Locale(identifier: "tr_TR")
        ) { placemarks, error in
            DispatchQueue.main.async {
                isGeocoding = false
                if let error { geocodeError = "Adres alınamadı: \(error.localizedDescription)"; return }
                guard let pm = placemarks?.first else {
                    geocodeError = "Bu konum için adres bulunamadı."; return
                }

                // ── İl ────────────────────────────────────────────────────
                // administrativeArea is reliably the province (il) in Turkey.
                let resolvedCity = pm.administrativeArea ?? pm.locality ?? ""
                city = resolvedCity

                // ── İlçe ──────────────────────────────────────────────────
                // subAdministrativeArea = ilçe in Turkey, but sometimes CLGeocoder
                // returns the il name here — fall back to locality in that case.
                let rawDistrict = pm.subAdministrativeArea ?? ""
                if rawDistrict.isEmpty || rawDistrict.caseInsensitiveCompare(resolvedCity) == .orderedSame {
                    district = pm.locality ?? resolvedCity
                } else {
                    district = rawDistrict
                }

                // ── Mahalle ───────────────────────────────────────────────
                // CLGeocoder (reverse) and MKLocalSearch (forward) use different
                // data sources and frequently disagree on subLocality in Turkey.
                // Strategy (priority order):
                //   1. MKLocalSearch hint subLocality  — most accurate when user
                //      searched by neighbourhood name (e.g. "Akbilek Mahallesi")
                //   2. Neighbourhood extracted from the search query name itself
                //      (strips "Mahallesi" / "Mah." suffix)
                //   3. CLGeocoder subLocality — only when different from il/ilçe
                //   4. Leave blank so the user can fill it manually
                neighborhood = Self.resolveNeighborhood(
                    hint: hint,
                    geocoderSubLocality: pm.subLocality,
                    city: resolvedCity,
                    district: district
                )

                // ── Sokak / Cadde ─────────────────────────────────────────
                // thoroughfare = road name; subThoroughfare = building number.
                // Keep them in separate fields instead of merging.
                street = pm.thoroughfare ?? hint?.thoroughfare ?? ""
                if buildingNo.isEmpty, let bldg = pm.subThoroughfare ?? hint?.subThoroughfare, !bldg.isEmpty {
                    buildingNo = bldg
                }

                withAnimation { step = 2 }
            }
        }
    }

    // MARK: - Neighbourhood resolution helper

    /// Picks the best neighbourhood string from available sources.
    private static func resolveNeighborhood(
        hint: MKPlacemark?,
        geocoderSubLocality: String?,
        city: String,
        district: String
    ) -> String {
        // 1. MKLocalSearch hint: subLocality from the forward-search placemark.
        if let hintLocality = hint?.subLocality,
           !hintLocality.isEmpty,
           hintLocality.caseInsensitiveCompare(city) != .orderedSame,
           hintLocality.caseInsensitiveCompare(district) != .orderedSame {
            return hintLocality
        }

        // 2. Extract from the hint placemark's name field.
        //    MKMapItem.name for a neighbourhood search is often "Akbilek Mahallesi".
        if let hintName = hint?.name {
            let extracted = Self.extractNeighborhoodName(from: hintName)
            if let extracted,
               extracted.caseInsensitiveCompare(city) != .orderedSame,
               extracted.caseInsensitiveCompare(district) != .orderedSame {
                return extracted
            }
        }

        // 3. CLGeocoder reverse-geocode subLocality — only when meaningfully
        //    different from il and ilçe.
        if let raw = geocoderSubLocality,
           !raw.isEmpty,
           raw.caseInsensitiveCompare(city) != .orderedSame,
           raw.caseInsensitiveCompare(district) != .orderedSame {
            return raw
        }

        // 4. Give up; user will fill it manually.
        return ""
    }

    /// Strips Turkish neighbourhood suffixes from a place name.
    /// "Akbilek Mahallesi" → "Akbilek", "Bağcılar Mah." → "Bağcılar"
    private static func extractNeighborhoodName(from name: String) -> String? {
        let suffixes = ["Mahallesi", "Mahalle", "Mah."]
        for suffix in suffixes {
            if let range = name.range(of: suffix, options: [.caseInsensitive, .backwards]) {
                let trimmed = String(name[name.startIndex..<range.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        // If name itself contains "Mahall" anywhere, treat the whole thing as mahalle.
        if name.localizedCaseInsensitiveContains("mahall") {
            return name.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    // MARK: - Save

    private func save() {
        guard let uid = viewModel.authService.currentUser?.id else { return }
        isSaving = true
        var addr = UserAddress(
            title: labelTitle, city: city, district: district,
            neighborhood: neighborhood, street: street,
            buildingNo: buildingNo, flatNo: flatNo,
            directions: directions, isDefault: isDefault
        )
        // Persist the map pin coordinates so the checkout preview is instant
        addr.latitude  = pinCoordinate.latitude
        addr.longitude = pinCoordinate.longitude
        addr.phone     = phone
        if let existing = existingAddress { addr.id = existing.id }
        viewModel.dataService.saveAddress(uid: uid, address: addr) { _ in
            isSaving = false
            if !city.isEmpty {
                viewModel.dataService.updateUserProfile(uid: uid, data: ["city": city]) { _ in
                    viewModel.authService.refreshCurrentUser()
                }
            }
            dismiss()
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Kayıtlı Kartlarım
// ═══════════════════════════════════════════════════════════════════

struct UserCardsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var cards: [SavedCard] = []
    @State private var isLoading = true
    @State private var showingAdd = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cards.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "creditcard.slash").font(.system(size: 44)).foregroundColor(.gray)
                    Text("Kayıtlı kart yok").foregroundColor(.secondary)
                    Button("Kart Ekle") { showingAdd = true }
                        .buttonStyle(.borderedProminent).tint(.orange)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(cards) { card in CardRow(card: card) { delete(card) } }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Kayıtlı Kartlarım")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .onAppear { fetch() }
        .sheet(isPresented: $showingAdd, onDismiss: { fetch() }) {
            AddCardView(viewModel: viewModel)
        }
    }

    private func fetch() {
        guard let uid = viewModel.authService.currentUser?.id else { isLoading = false; return }
        isLoading = true
        viewModel.dataService.fetchCards(uid: uid) { result in cards = result; isLoading = false }
    }

    private func delete(_ card: SavedCard) {
        guard let uid = viewModel.authService.currentUser?.id else { return }
        viewModel.dataService.deleteCard(uid: uid, cardId: card.id) { _ in
            cards.removeAll { $0.id == card.id }
        }
    }
}

private struct CardRow: View {
    let card: SavedCard; let onDelete: () -> Void
    private var cardIcon: String {
        switch card.cardType.lowercased() {
        case "visa": return "v.circle.fill"
        case "mastercard": return "m.circle.fill"
        default: return "creditcard.fill"
        }
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: cardIcon).font(.title2).foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.alias).fontWeight(.semibold)
                Text("•••• •••• •••• \(card.lastFour)").font(.caption).foregroundColor(.secondary)
                Text("Son kullanım: \(card.expiryMonth)/\(card.expiryYear)").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if card.isDefault {
                Text("Varsayılan").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12)).foregroundColor(.blue).cornerRadius(4)
            }
            Button { onDelete() } label: { Image(systemName: "trash").foregroundColor(.red).font(.caption) }
        }
        .padding(.vertical, 4)
    }
}

struct AddCardView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var alias = ""
    @State private var cardHolder = ""
    @State private var lastFour = ""
    @State private var expiryMonth = "01"
    @State private var expiryYear = "2027"
    @State private var cardType = "Visa"
    @State private var isDefault = false
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    let cardTypes = ["Visa", "Mastercard", "Troy", "Amex"]
    let months = (1...12).map { String(format: "%02d", $0) }
    let years  = (2024...2035).map { String($0) }
    private var isValid: Bool { !alias.isEmpty && lastFour.count == 4 && !cardHolder.isEmpty }

    var body: some View {
        NavigationView {
            Form {
                Section("Kart Bilgileri") {
                    TextField("Kart adı (ör: Benim Kartım)", text: $alias)
                    TextField("Kart sahibi adı", text: $cardHolder)
                    Picker("Kart tipi", selection: $cardType) {
                        ForEach(cardTypes, id: \.self) { Text($0) }
                    }
                }
                Section("Son 4 Hane") {
                    TextField("1234", text: $lastFour).keyboardType(.numberPad)
                        .onChange(of: lastFour) { v in if v.count > 4 { lastFour = String(v.prefix(4)) } }
                }
                Section("Son Kullanım Tarihi") {
                    HStack {
                        Picker("Ay", selection: $expiryMonth) {
                            ForEach(months, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.wheel).frame(width: 80, height: 80).clipped()
                        Text("/").foregroundColor(.secondary)
                        Picker("Yıl", selection: $expiryYear) {
                            ForEach(years, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.wheel).frame(width: 100, height: 80).clipped()
                    }
                }
                Section {
                    Toggle("Varsayılan kart olarak ayarla", isOn: $isDefault)
                }
            }
            .navigationTitle("Kart Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else {
                        Button("Kaydet") { save() }.disabled(!isValid)
                    }
                }
            }
        }
    }

    private func save() {
        guard let uid = viewModel.authService.currentUser?.id else { return }
        isSaving = true
        let card = SavedCard(alias: alias, lastFour: lastFour, cardHolderName: cardHolder,
                             expiryMonth: expiryMonth, expiryYear: expiryYear,
                             cardType: cardType, isDefault: isDefault)
        viewModel.dataService.saveCard(uid: uid, card: card) { _ in isSaving = false; dismiss() }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - E-posta Değişikliği
// ═══════════════════════════════════════════════════════════════════

struct EmailChangeView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var newEmail = ""
    @State private var currentPassword = ""
    @State private var isSaving = false
    @State private var message: String?
    @State private var isSuccess = false

    var body: some View {
        Form {
            Section("Mevcut E-posta") {
                HStack {
                    Text(viewModel.authService.currentUser?.email ?? "")
                    Spacer()
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                }
            }
            Section("Yeni Bilgiler") {
                TextField("Yeni e-posta adresi", text: $newEmail)
                    .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                SecureField("Mevcut şifreniz (onay için)", text: $currentPassword)
            }
            if let msg = message {
                Section {
                    Text(msg).foregroundColor(isSuccess ? .green : .red).font(.caption)
                }
            }
            Section {
                Button { save() } label: {
                    if isSaving { ProgressView() } else {
                        Text("E-postayı Güncelle").frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSaving || newEmail.isEmpty || currentPassword.isEmpty)
            }
            Section {
                Text("E-posta değişikliği için mevcut şifreniz gereklidir. Değişiklik sonrasında yeni adresinizle giriş yapınız.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .navigationTitle("E-posta Değişikliği")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        isSaving = true; message = nil
        viewModel.authService.updateEmail(newEmail: newEmail, currentPassword: currentPassword) { error in
            isSaving = false
            if let error { message = error.localizedDescription; isSuccess = false }
            else { message = "E-posta başarıyla güncellendi ✓"; isSuccess = true; newEmail = ""; currentPassword = "" }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Duyuru Tercihleri
// ═══════════════════════════════════════════════════════════════════

struct NotificationPrefsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var prefs = NotificationPreferences()
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showSuccess = false

    var body: some View {
        Form {
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else {
                Section("Push Bildirimleri") {
                    Toggle("Sipariş güncellemeleri", isOn: $prefs.orderUpdates)
                    Toggle("Kampanya ve promosyonlar", isOn: $prefs.promotions)
                    Toggle("Yeni mağazalar", isOn: $prefs.newRestaurants)
                }
                Section("E-posta") {
                    Toggle("Haftalık özet e-postası", isOn: $prefs.emailDigest)
                }
                Section {
                    Button { save() } label: {
                        if isSaving { ProgressView() } else {
                            Text("Tercihleri Kaydet").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isSaving)
                }
                if showSuccess {
                    Section {
                        Text("Tercihler kaydedildi ✓").foregroundColor(.green).font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Duyuru Tercihleri")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { fetch() }
    }

    private func fetch() {
        guard let uid = viewModel.authService.currentUser?.id else { isLoading = false; return }
        viewModel.dataService.fetchNotificationPreferences(uid: uid) { result in
            prefs = result; isLoading = false
        }
    }

    private func save() {
        guard let uid = viewModel.authService.currentUser?.id else { return }
        isSaving = true; showSuccess = false
        viewModel.dataService.saveNotificationPreferences(uid: uid, prefs: prefs) { _ in
            isSaving = false; showSuccess = true
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Şifre Değiştir
// ═══════════════════════════════════════════════════════════════════

struct ChangePasswordView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var message: String?
    @State private var isSuccess = false

    private var isValid: Bool {
        !currentPassword.isEmpty && newPassword.count >= 6 && newPassword == confirmPassword
    }

    var body: some View {
        Form {
            Section("Mevcut Şifre") {
                SecureField("Mevcut şifreniz", text: $currentPassword)
            }
            Section("Yeni Şifre") {
                SecureField("Yeni şifre (en az 6 karakter)", text: $newPassword)
                SecureField("Yeni şifreyi tekrar girin", text: $confirmPassword)
                if !newPassword.isEmpty && !confirmPassword.isEmpty && newPassword != confirmPassword {
                    Text("Şifreler eşleşmiyor").font(.caption).foregroundColor(.red)
                }
            }
            if let msg = message {
                Section {
                    Text(msg).foregroundColor(isSuccess ? .green : .red).font(.caption)
                }
            }
            Section {
                Button { save() } label: {
                    if isSaving { ProgressView() } else {
                        Text("Şifreyi Güncelle").frame(maxWidth: .infinity)
                    }
                }
                .disabled(!isValid || isSaving)
            }
        }
        .navigationTitle("Şifre Değiştir")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        isSaving = true; message = nil
        viewModel.authService.changePassword(currentPassword: currentPassword, newPassword: newPassword) { error in
            isSaving = false
            if let error { message = error.localizedDescription; isSuccess = false }
            else {
                message = "Şifre başarıyla güncellendi ✓"; isSuccess = true
                currentPassword = ""; newPassword = ""; confirmPassword = ""
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Giriş Bilgileri
// ═══════════════════════════════════════════════════════════════════

struct LoginHistoryView: View {
    @ObservedObject var viewModel: AppViewModel

    private var lastSignIn: String {
        guard let date = viewModel.authService.getLastSignInDate() else { return "Bilinmiyor" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateStyle = .long; f.timeStyle = .short
        return f.string(from: date)
    }

    var body: some View {
        Form {
            Section("Son Başarılı Giriş") {
                Label(lastSignIn, systemImage: "clock.fill").foregroundColor(.teal)
            }
            Section("Aktif Oturumlar") {
                HStack(spacing: 12) {
                    Image(systemName: "iphone").font(.title2).foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bu Cihaz").fontWeight(.semibold)
                        Text("iOS  •  Şu an aktif").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("Aktif").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.green.opacity(0.15)).foregroundColor(.green).cornerRadius(4)
                }
            }
            Section {
                Button(role: .destructive) {
                    viewModel.authService.signOut()
                } label: {
                    Label("Tüm Oturumları Kapat", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            Section {
                Text("Birden fazla cihaz oturumu yönetimi yakında eklenecek.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .navigationTitle("Giriş Bilgileri")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Daha Fazla (static pages)
// ═══════════════════════════════════════════════════════════════════

struct HelpSupportView: View {
    var body: some View {
        List {
            Section("Sık Sorulan Sorular") {
                DisclosureGroup("Siparişimi nasıl takip ederim?") {
                    Text("Siparişlerim sayfasından aktif siparişinizi takip edebilirsiniz.").font(.caption)
                }
                DisclosureGroup("Siparişimi iptal etmek istiyorum") {
                    Text("Hazırlanma aşamasından önce Siparişlerim sayfasından iptal edebilirsiniz.").font(.caption)
                }
                DisclosureGroup("Ödeme sorunum var") {
                    Text("Kart bilgilerinizi kontrol edin veya bizimle iletişime geçin.").font(.caption)
                }
            }
            Section("İletişim") {
                Link(destination: URL(string: "mailto:destek@yemeksepeti.com")!) {
                    Label("E-posta ile İletişim", systemImage: "envelope.fill")
                }
                Link(destination: URL(string: "tel:08501234567")!) {
                    Label("Müşteri Hattı: 0850 123 45 67", systemImage: "phone.fill")
                }
            }
        }
        .navigationTitle("Yardım & Destek")
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Gizlilik Politikası")
                    .font(.title2).fontWeight(.bold)
                Text("Bu uygulama, kişisel verilerinizi yalnızca hizmet sunumu için toplar ve üçüncü taraflarla paylaşmaz.")
                Text("Toplanan veriler: e-posta adresi, teslimat adresleri, sipariş geçmişi.")
                Text("Verilerinizi silmek için destek@yemeksepeti.com adresine başvurabilirsiniz.")
            }
            .padding()
        }
        .navigationTitle("Gizlilik Politikası")
    }
}

struct AboutAppView: View {
    var body: some View {
        List {
            Section {
                HStack { Text("Uygulama"); Spacer(); Text("Yemeksepeti").foregroundColor(.secondary) }
                HStack { Text("Versiyon"); Spacer(); Text("1.0.0").foregroundColor(.secondary) }
                HStack { Text("Platform"); Spacer(); Text("iOS 17+").foregroundColor(.secondary) }
            }
            Section("Geliştirici") {
                HStack { Text("Geliştirici"); Spacer(); Text("Ertugrul Ozer").foregroundColor(.secondary) }
            }
        }
        .navigationTitle("Hakkında")
    }
}
