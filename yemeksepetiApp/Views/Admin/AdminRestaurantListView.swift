import SwiftUI

struct AdminRestaurantListView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var restaurants: [Restaurant] = []
    @State private var showingAddRestaurant = false
    @State private var isLoading = false
    @State private var restaurantToDelete: Restaurant? = nil
    @State private var showingDeleteConfirm = false
    @State private var alertMessage: String?
    @State private var showingAlert = false

    var body: some View {
        List {
            ForEach(restaurants) { restaurant in
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
                        // Aktif/Pasif göstergesi
                        Image(systemName: restaurant.isActive ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(restaurant.isActive ? .green : .red)
                        // Admin-only silme butonu
                        Button {
                            restaurantToDelete = restaurant
                            showingDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .padding(.leading, 8)
                        }
                        .buttonStyle(.plain) // NavigationLink içinde tap çakışmaması için
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Restoranlar")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAddRestaurant = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear(perform: loadRestaurants)
        .sheet(isPresented: $showingAddRestaurant) {
            AddRestaurantView(dataService: viewModel.dataService, onAdd: {
                loadRestaurants()
                showingAddRestaurant = false
            })
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
            self.isLoading = false
        }
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
