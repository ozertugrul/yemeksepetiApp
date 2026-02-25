import SwiftUI
import Combine

struct AdminRestaurantListView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var adminVM: AdminViewModel

    // UI-only state
    @State private var showingAddRestaurant   = false
    @State private var restaurantToDelete: Restaurant?
    @State private var showingDeleteConfirm   = false
    @State private var alertMessage: String?
    @State private var showingAlert           = false
    @State private var showingCityFilter      = false
    @State private var showingCuisineFilter   = false

    private var activeFilterCount: Int {
        (adminVM.restaurantCityFilter    != nil ? 1 : 0) +
        (adminVM.restaurantCuisineFilter != nil ? 1 : 0) +
        (adminVM.restaurantActiveFilter  != nil ? 1 : 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            filterChipsRow
            Divider()
            resultsBadge
            errorBanner
            contentArea
        }
        .navigationTitle(adminVM.restaurants.isEmpty
            ? "Restoranlar"
            : "Restoranlar (\(adminVM.restaurantTotal))")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAddRestaurant = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear {
            if adminVM.restaurants.isEmpty { adminVM.reloadRestaurants() }
        }
        .refreshable { adminVM.reloadRestaurants() }
        .sheet(isPresented: $showingAddRestaurant) {
            AddRestaurantView(dataService: viewModel.dataService) {
                adminVM.reloadRestaurants()
                showingAddRestaurant = false
            }
        }
        .sheet(isPresented: $showingCityFilter)    { cityFilterSheet }
        .sheet(isPresented: $showingCuisineFilter) { cuisineFilterSheet }
        .confirmationDialog(
            restaurantToDelete.map { "\'\($0.name)\' silinsin mi?" } ?? "Restoran Sil",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Evet, Kalici Olarak Sil", role: .destructive) {
                if let r = restaurantToDelete { performDelete(r) }
            }
            Button("Iptal", role: .cancel) { restaurantToDelete = nil }
        } message: {
            Text("Bu islem geri alinamaz. Restorana ait tum menu ogeleri de silinir.")
        }
        .alert(alertMessage ?? "", isPresented: $showingAlert) {
            Button("Tamam", role: .cancel) {}
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.gray)
                TextField("Restoran adi, mutfak veya sehir ara...",
                          text: $adminVM.restaurantSearchQuery)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                if !adminVM.restaurantSearchQuery.isEmpty {
                    Button { adminVM.restaurantSearchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            if adminVM.isLoadingRestaurants { ProgressView().padding(.trailing, 4) }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let counts = adminVM.restaurantActiveCounts
                FilterChip(label: "Aktif", isActive: adminVM.restaurantActiveFilter == true,
                           color: .green, count: counts.active) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        adminVM.restaurantActiveFilter = adminVM.restaurantActiveFilter == true ? nil : true
                    }
                }
                FilterChip(label: "Pasif", isActive: adminVM.restaurantActiveFilter == false,
                           color: .red, count: counts.passive) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        adminVM.restaurantActiveFilter = adminVM.restaurantActiveFilter == false ? nil : false
                    }
                }
                Divider().frame(height: 24)
                FilterChip(
                    label: adminVM.restaurantCityFilter ?? "Sehir",
                    isActive: adminVM.restaurantCityFilter != nil,
                    color: .blue, icon: "mappin.circle.fill"
                ) { showingCityFilter = true }
                FilterChip(
                    label: adminVM.restaurantCuisineFilter ?? "Mutfak",
                    isActive: adminVM.restaurantCuisineFilter != nil,
                    color: .orange, icon: "fork.knife"
                ) { showingCuisineFilter = true }
                if activeFilterCount > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            adminVM.restaurantCityFilter    = nil
                            adminVM.restaurantCuisineFilter = nil
                            adminVM.restaurantActiveFilter  = nil
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

    @ViewBuilder
    private var resultsBadge: some View {
        if !adminVM.restaurantSearchQuery.isEmpty || activeFilterCount > 0 {
            HStack {
                Text("\(adminVM.restaurants.count) / \(adminVM.restaurantTotal) restoran")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal).padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let err = adminVM.restaurantError {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text(err).font(.caption).foregroundColor(.orange)
                Spacer()
                Button("Tekrar Dene") { adminVM.reloadRestaurants() }
                    .font(.caption).foregroundColor(.blue)
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if adminVM.isLoadingRestaurants && adminVM.restaurants.isEmpty {
            Spacer()
            ProgressView("Restoranlar yukleniyor...")
            Spacer()
        } else if adminVM.restaurants.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: activeFilterCount > 0 || !adminVM.restaurantSearchQuery.isEmpty
                    ? "magnifyingglass" : "building.2.slash")
                    .font(.system(size: 44)).foregroundColor(.gray)
                Text(activeFilterCount > 0 || !adminVM.restaurantSearchQuery.isEmpty
                    ? "Sonuc bulunamadi" : "Henuz restoran yok")
                    .foregroundColor(.secondary)
                if activeFilterCount > 0 {
                    Button("Filtreleri Temizle") {
                        adminVM.restaurantCityFilter    = nil
                        adminVM.restaurantCuisineFilter = nil
                        adminVM.restaurantActiveFilter  = nil
                        adminVM.restaurantSearchQuery   = ""
                    }
                    .font(.caption).foregroundColor(.orange)
                }
            }
            Spacer()
        } else {
            List {
                ForEach(adminVM.restaurants) { restaurant in
                    NavigationLink(destination: EditRestaurantView(
                        restaurant: restaurant,
                        dataService: viewModel.dataService,
                        onSave: { adminVM.reloadRestaurants() }
                    )) {
                        restaurantRow(restaurant)
                    }
                }
                if adminVM.hasMoreRestaurants {
                    HStack {
                        Spacer()
                        if adminVM.isLoadingRestaurants {
                            ProgressView().padding(.vertical, 8)
                        } else {
                            Text("Daha fazla yukle")
                                .font(.caption).foregroundColor(.secondary).padding(.vertical, 8)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { adminVM.loadMoreRestaurants() }
                    .onAppear    { adminVM.loadMoreRestaurants() }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func restaurantRow(_ restaurant: Restaurant) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(restaurant.name).font(.headline)
                Text(restaurant.cuisineType).font(.subheadline).foregroundColor(.gray)
                if let city = restaurant.city, !city.isEmpty {
                    Text(city).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Image(systemName: restaurant.isActive ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(restaurant.isActive ? .green : .red)
            Button {
                restaurantToDelete   = restaurant
                showingDeleteConfirm = true
            } label: {
                Image(systemName: "trash").foregroundColor(.red).padding(.leading, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var cityFilterSheet: some View {
        NavigationView {
            List {
                Button { adminVM.restaurantCityFilter = nil; showingCityFilter = false } label: {
                    HStack {
                        Text("Tum Sehirler").foregroundColor(.primary)
                        Spacer()
                        if adminVM.restaurantCityFilter == nil {
                            Image(systemName: "checkmark").foregroundColor(.orange)
                        }
                    }
                }
                ForEach(adminVM.restaurantDistinctCities, id: \.self) { city in
                    Button { adminVM.restaurantCityFilter = city; showingCityFilter = false } label: {
                        HStack {
                            Text(city).foregroundColor(.primary)
                            Spacer()
                            if adminVM.restaurantCityFilter == city {
                                Image(systemName: "checkmark").foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Sehir Filtresi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Iptal") { showingCityFilter = false }
                }
            }
        }
        .if_iOS16_presentationDetents()
    }

    @ViewBuilder private var cuisineFilterSheet: some View {
        NavigationView {
            List {
                Button { adminVM.restaurantCuisineFilter = nil; showingCuisineFilter = false } label: {
                    HStack {
                        Text("Tum Mutfaklar").foregroundColor(.primary)
                        Spacer()
                        if adminVM.restaurantCuisineFilter == nil {
                            Image(systemName: "checkmark").foregroundColor(.orange)
                        }
                    }
                }
                ForEach(adminVM.restaurantDistinctCuisines, id: \.self) { cuisine in
                    Button { adminVM.restaurantCuisineFilter = cuisine; showingCuisineFilter = false } label: {
                        HStack {
                            Text(cuisine).foregroundColor(.primary)
                            Spacer()
                            if adminVM.restaurantCuisineFilter == cuisine {
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
                    Button("Iptal") { showingCuisineFilter = false }
                }
            }
        }
        .if_iOS16_presentationDetents()
    }

    private func performDelete(_ restaurant: Restaurant) {
        Task {
            do {
                try await adminVM.performDeleteRestaurant(id: restaurant.id)
                restaurantToDelete = nil
            } catch {
                alertMessage = "Silme hatasi: \(error.localizedDescription)"
                showingAlert = true
                restaurantToDelete = nil
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
