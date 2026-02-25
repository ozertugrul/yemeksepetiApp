import SwiftUI
import Combine

struct AdminRestaurantListView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var restaurants: [Restaurant] = []
    @State private var showingAddRestaurant = false
    @State private var isLoading = false
    @State private var restaurantToDelete: Restaurant? = nil
    @State private var showingDeleteConfirm = false
    @State private var alertMessage: String?
    @State private var showingAlert = false
    // Search & Filters
    @State private var searchQuery = ""
    @State private var debouncedQuery = ""
    @State private var selectedCityFilter: String? = nil
    @State private var selectedCuisineFilter: String? = nil
    @State private var selectedActiveFilter: Bool? = nil
    @State private var showingCityFilter = false
    @State private var showingCuisineFilter = false
    // Önbellek (body'de hesaplanmaz)
    @State private var activeCount = 0
    @State private var passiveCount = 0
    @State private var cachedCities: [String] = []
    @State private var cachedCuisines: [String] = []
    @State private var cityCountsMap: [String: Int] = [:]
    @State private var cuisineCountsMap: [String: Int] = [:]
    // Debounce
    @State private var searchCancellable: AnyCancellable?
    @State private var searchSubject = PassthroughSubject<String, Never>()

    private var filteredRestaurants: [Restaurant] {
        var result = restaurants
        // Şehir
        if let city = selectedCityFilter {
            result = result.filter { ($0.city ?? "").lowercased() == city.lowercased() }
        }
        // Mutfak
        if let cuisine = selectedCuisineFilter {
            result = result.filter { $0.cuisineType == cuisine }
        }
        // Aktif/Pasif
        if let active = selectedActiveFilter {
            result = result.filter { $0.isActive == active }
        }
        // Arama (debounced)
        let q = debouncedQuery
        if !q.isEmpty {
            result = result.filter {
                $0.name.lowercased().contains(q) ||
                $0.cuisineType.lowercased().contains(q) ||
                ($0.city ?? "").lowercased().contains(q)
            }
        }
        return result
    }

    private var activeFilterCount: Int {
        var c = 0
        if selectedCityFilter != nil { c += 1 }
        if selectedCuisineFilter != nil { c += 1 }
        if selectedActiveFilter != nil { c += 1 }
        return c
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Search bar ───────────────────────────────────────────
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.gray)
                    TextField("Restoran adı, mutfak veya şehir ara...", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .onChange(of: searchQuery) { newValue in
                            searchSubject.send(newValue)
                        }
                    if !searchQuery.isEmpty {
                        Button { searchQuery = ""; debouncedQuery = "" } label: {
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

            // ── Filter chips ────────────────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Aktif/Pasif
                    FilterChip(label: "Aktif", isActive: selectedActiveFilter == true, color: .green,
                               count: activeCount) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedActiveFilter = selectedActiveFilter == true ? nil : true
                        }
                    }
                    FilterChip(label: "Pasif", isActive: selectedActiveFilter == false, color: .red,
                               count: passiveCount) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedActiveFilter = selectedActiveFilter == false ? nil : false
                        }
                    }

                    Divider().frame(height: 24)

                    // Şehir
                    FilterChip(
                        label: selectedCityFilter ?? "Şehir",
                        isActive: selectedCityFilter != nil,
                        color: .blue,
                        icon: "mappin.circle.fill"
                    ) {
                        showingCityFilter = true
                    }

                    // Mutfak
                    FilterChip(
                        label: selectedCuisineFilter ?? "Mutfak",
                        isActive: selectedCuisineFilter != nil,
                        color: .orange,
                        icon: "fork.knife"
                    ) {
                        showingCuisineFilter = true
                    }

                    // Temizle
                    if activeFilterCount > 0 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCityFilter = nil
                                selectedCuisineFilter = nil
                                selectedActiveFilter = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 6)

            Divider()

            // ── Results info ───────────────────────────────────────
            if !searchQuery.isEmpty || activeFilterCount > 0 {
                HStack {
                    Text("\(filteredRestaurants.count) / \(restaurants.count) restoran")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal).padding(.vertical, 4)
            }

            // ── List ─────────────────────────────────────────────
            if isLoading && restaurants.isEmpty {
                Spacer()
                ProgressView("Restoranlar yükleniyor...")
                Spacer()
            } else if filteredRestaurants.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: restaurants.isEmpty ? "building.2.slash" : "magnifyingglass")
                        .font(.system(size: 44)).foregroundColor(.gray)
                    Text(restaurants.isEmpty ? "Henüz restoran yok" : "Sonuç bulunamadı")
                        .foregroundColor(.secondary)
                    if activeFilterCount > 0 {
                        Button("Filtreleri Temizle") {
                            selectedCityFilter = nil
                            selectedCuisineFilter = nil
                            selectedActiveFilter = nil
                            searchQuery = ""
                        }
                        .font(.caption).foregroundColor(.orange)
                    }
                }
                Spacer()
            } else {
                List(filteredRestaurants) { restaurant in
                    NavigationLink(destination: EditRestaurantView(
                        restaurant: restaurant,
                        dataService: viewModel.dataService,
                        onSave: { loadRestaurants() }
                    )) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(restaurant.name)
                                    .font(.headline)
                                Text(restaurant.cuisineType)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                if let city = restaurant.city, !city.isEmpty {
                                    Text(city)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: restaurant.isActive ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(restaurant.isActive ? .green : .red)
                            Button {
                                restaurantToDelete = restaurant
                                showingDeleteConfirm = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                    .padding(.leading, 8)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(restaurants.isEmpty ? "Restoranlar" : "Restoranlar (\(restaurants.count))")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAddRestaurant = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear {
            loadRestaurants()
            searchCancellable = searchSubject
                .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .removeDuplicates()
                .sink { debouncedQuery = $0 }
        }
        .onDisappear {
            searchCancellable?.cancel()
        }
        .sheet(isPresented: $showingAddRestaurant) {
            AddRestaurantView(dataService: viewModel.dataService, onAdd: {
                loadRestaurants()
                showingAddRestaurant = false
            })
        }
        // Şehir filtre sheet
        .sheet(isPresented: $showingCityFilter) {
            NavigationView {
                List {
                    Button {
                        selectedCityFilter = nil
                        showingCityFilter = false
                    } label: {
                        HStack {
                            Text("Tüm Şehirler").foregroundColor(.primary)
                            Spacer()
                            if selectedCityFilter == nil {
                                Image(systemName: "checkmark").foregroundColor(.orange)
                            }
                        }
                    }
                    ForEach(cachedCities, id: \.self) { city in
                        Button {
                            selectedCityFilter = city
                            showingCityFilter = false
                        } label: {
                            HStack {
                                Text(city).foregroundColor(.primary)
                                Spacer()
                                Text("\(cityCountsMap[city] ?? 0)").font(.caption).foregroundColor(.secondary)
                                if selectedCityFilter == city {
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
        // Mutfak filtre sheet
        .sheet(isPresented: $showingCuisineFilter) {
            NavigationView {
                List {
                    Button {
                        selectedCuisineFilter = nil
                        showingCuisineFilter = false
                    } label: {
                        HStack {
                            Text("Tüm Mutfaklar").foregroundColor(.primary)
                            Spacer()
                            if selectedCuisineFilter == nil {
                                Image(systemName: "checkmark").foregroundColor(.orange)
                            }
                        }
                    }
                    ForEach(cachedCuisines, id: \.self) { cuisine in
                        Button {
                            selectedCuisineFilter = cuisine
                            showingCuisineFilter = false
                        } label: {
                            HStack {
                                Text(cuisine).foregroundColor(.primary)
                                Spacer()
                                Text("\(cuisineCountsMap[cuisine] ?? 0)").font(.caption).foregroundColor(.secondary)
                                if selectedCuisineFilter == cuisine {
                                    Image(systemName: "checkmark").foregroundColor(.orange)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .navigationTitle("Mutfak Filtresi")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("İptal") { showingCuisineFilter = false }
                    }
                }
            }
            .if_iOS16_presentationDetents()
        }
        // ── Silme onay diyaloğu ───────────────────────────────────────────────
        .confirmationDialog(
            restaurantToDelete.map { "'\($0.name)' silinsin mi?" } ?? "Restoran Sil",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Evet, Kalıcı Olarak Sil", role: .destructive) {
                if let r = restaurantToDelete { deleteRestaurant(r) }
            }
            Button("İptal", role: .cancel) { restaurantToDelete = nil }
        } message: {
            Text("Bu işlem geri alınamaz. Restorana ait tüm menü öğeleri de silinir.")
        }
        .alert(alertMessage ?? "", isPresented: $showingAlert) {
            Button("Tamam", role: .cancel) {}
        }
    }

    // MARK: - Actions

    func loadRestaurants() {
        isLoading = true
        viewModel.dataService.getAllRestaurantsForAdmin { fetchedRestaurants in
            self.restaurants = fetchedRestaurants
            self.recalculateCachedCounts(for: fetchedRestaurants)
            self.isLoading = false
        }
    }

    /// Sayıları bir kez hesapla, body’den çıkar
    private func recalculateCachedCounts(for list: [Restaurant]) {
        var aCount = 0, pCount = 0
        var cityMap: [String: Int] = [:]
        var cuisineMap: [String: Int] = [:]
        for r in list {
            if r.isActive { aCount += 1 } else { pCount += 1 }
            if let c = r.city, !c.isEmpty { cityMap[c, default: 0] += 1 }
            if !r.cuisineType.isEmpty { cuisineMap[r.cuisineType, default: 0] += 1 }
        }
        activeCount = aCount
        passiveCount = pCount
        cityCountsMap = cityMap
        cuisineCountsMap = cuisineMap
        cachedCities = cityMap.keys.sorted()
        cachedCuisines = cuisineMap.keys.sorted()
    }

    private func deleteRestaurant(_ restaurant: Restaurant) {
        Task {
            do {
                try await viewModel.adminAPI.deleteRestaurant(id: restaurant.id)
                await MainActor.run {
                    restaurants.removeAll { $0.id == restaurant.id }
                    restaurantToDelete = nil
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Silme hatası: \(error.localizedDescription)"
                    showingAlert = true
                    restaurantToDelete = nil
                }
            }
        }
    }
}


struct AddRestaurantView: View {
    @State private var name = ""
    @State private var cuisine = ""
    @State private var minOrderAmount = ""
    @State private var isActive = true
    @State private var city = ""
    @State private var showingCityPicker = false
    @Environment(\.dismiss) private var dismiss
    let dataService: DataService
    var onAdd: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Genel Bilgiler")) {
                    TextField("Restoran Adı", text: $name)
                    TextField("Mutfak Türü (Örn: Burger, Pizza)", text: $cuisine)
                    Toggle("Aktif mi?", isOn: $isActive)
                }
                
                Section(header: Text("Detaylar")) {
                     TextField("Min. Sipariş Tutarı", text: $minOrderAmount)
                         .keyboardType(.decimalPad)
                }
                
                Section(header: Text("Konum")) {
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
                
                Button("Oluştur") {
                    createRestaurant()
                }
                .disabled(name.isEmpty || cuisine.isEmpty)
            }
            .navigationTitle("Yeni Restoran")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCityPicker) {
                CityPickerSheet(selectedCity: $city)
            }
        }
    }
    
    func createRestaurant() {
        let minOrder = Double(minOrderAmount) ?? 0.0
        let newRestaurant = Restaurant(
            id: UUID().uuidString,
            name: name,
            ownerId: nil,
            description: "",
            cuisineType: cuisine,
            imageUrl: nil,
            rating: 5.0,
            deliveryTime: "30-45 dk",
            minOrderAmount: minOrder,
            menu: [],
            isActive: isActive,
            city: city.isEmpty ? nil : city
        )
        
        dataService.createRestaurant(restaurant: newRestaurant) { error in
            if let error = error {
                print("Error creating restaurant: \(error.localizedDescription)")
            } else {
                onAdd()
            }
        }
    }
}

struct EditRestaurantView: View {
    @State var restaurant: Restaurant
    let dataService: DataService
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draftCity = ""
    @State private var showingCityPicker = false
    
    var body: some View {
        Form {
            Section(header: Text("Genel Bilgiler")) {
                TextField("Restoran Adı", text: $restaurant.name)
                TextField("Mutfak Türü", text: $restaurant.cuisineType)
                TextField("Açıklama", text: $restaurant.description)
                Toggle("Aktif mi?", isOn: $restaurant.isActive)
            }
            
            Section(header: Text("Sipariş Bilgileri")) {
                 TextField("Teslimat Süresi", text: $restaurant.deliveryTime)
                 TextField("Min. Sipariş Tutarı", value: $restaurant.minOrderAmount, formatter: NumberFormatter())
            }
            
            Section(header: Text("Konum")) {
                Button { showingCityPicker = true } label: {
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
        }
        .navigationTitle("Restoran Düzenle")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet") { saveChanges() }
            }
        }
        .onAppear { draftCity = restaurant.city ?? "" }
        .sheet(isPresented: $showingCityPicker) {
            CityPickerSheet(selectedCity: $draftCity)
        }
    }
    
    func saveChanges() {
        restaurant.city = draftCity.isEmpty ? nil : draftCity
        dataService.updateRestaurant(restaurant: restaurant) { error in
             if let error = error {
                 print("Update error: \(error.localizedDescription)")
             } else {
                 onSave()
                 dismiss()
             }
        }
    }
}
