import SwiftUI

struct AdminRestaurantListView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var restaurants: [Restaurant] = []
    @State private var showingAddRestaurant = false
    @State private var isLoading = false
    
    var body: some View {
        List {
                ForEach(restaurants) { restaurant in
                    NavigationLink(destination: EditRestaurantView(
                        restaurant: restaurant,
                        dataService: DataService(),
                        onSave: { loadRestaurants() }
                    )) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(restaurant.name)
                                    .font(.headline)
                                Text(restaurant.cuisineType)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            if restaurant.isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteRestaurant)
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
                AddRestaurantView(onAdd: {
                    loadRestaurants()
                    showingAddRestaurant = false
                })
            }
    }
    
    func loadRestaurants() {
        isLoading = true
        let ds = DataService()
        // Here we want ALL restaurants, not just active ones
        ds.getAllRestaurantsForAdmin { fetchedRestaurants in
            self.restaurants = fetchedRestaurants
            self.isLoading = false
        }
    }
    
    func deleteRestaurant(at offsets: IndexSet) {
        let ds = DataService()
        offsets.forEach { index in
            let restaurant = restaurants[index]
            ds.deleteRestaurant(restaurantId: restaurant.id) { error in
                if let error = error {
                    print("Error deleting restaurant: \(error.localizedDescription)")
                }
            }
        }
        restaurants.remove(atOffsets: offsets)
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
        
        DataService().createRestaurant(restaurant: newRestaurant) { error in
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
