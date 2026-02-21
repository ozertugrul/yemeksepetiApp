import Foundation
import SwiftUI

// MARK: - UserAddress

struct UserAddress: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String           // "Ev", "İş", "Okul"
    var city: String
    var district: String
    var neighborhood: String
    var street: String
    var buildingNo: String
    var flatNo: String
    var directions: String      // Kapı tarifi
    var isDefault: Bool = false
    var phone: String = ""      // Teslimat iletişim numarası
    var latitude: Double?       // stored from map pin
    var longitude: Double?

    var fullAddress: String {
        var parts: [String] = []
        if !street.isEmpty         { parts.append(street + (buildingNo.isEmpty ? "" : " No:\(buildingNo)") + (flatNo.isEmpty ? "" : "/\(flatNo)")) }
        if !neighborhood.isEmpty   { parts.append(neighborhood) }
        if !district.isEmpty       { parts.append(district) }
        if !city.isEmpty           { parts.append(city) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - SavedCard

struct SavedCard: Identifiable, Codable {
    var id: String = UUID().uuidString
    var alias: String           // "Benim Kartım"
    var lastFour: String
    var cardHolderName: String
    var expiryMonth: String
    var expiryYear: String
    var cardType: String        // "Visa", "Mastercard", "Troy", "Amex"
    var isDefault: Bool = false
}

// MARK: - DiscountCoupon

struct DiscountCoupon: Identifiable, Codable {
    var id: String = UUID().uuidString
    var code: String
    var description: String
    var discountAmount: Double = 0
    var discountPercent: Double = 0
    var minimumOrderAmount: Double = 0
    var expiryDate: Date
    var isUsed: Bool = false

    var isExpired: Bool { expiryDate < Date() }
    var isValid: Bool { !isUsed && !isExpired }

    var formattedExpiry: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "dd.MM.yyyy"
        return f.string(from: expiryDate)
    }
}

// MARK: - NotificationPreferences

struct NotificationPreferences: Codable {
    var orderUpdates: Bool = true
    var promotions: Bool = true
    var newRestaurants: Bool = false
    var emailDigest: Bool = true
}

// MARK: - Turkish Cities (81 İl)

let TurkishCities: [String] = [
    "Adana", "Adıyaman", "Afyonkarahisar", "Ağrı", "Aksaray", "Amasya",
    "Ankara", "Antalya", "Ardahan", "Artvin", "Aydın", "Balıkesir",
    "Bartın", "Batman", "Bayburt", "Bilecik", "Bingöl", "Bitlis",
    "Bolu", "Burdur", "Bursa", "Çanakkale", "Çankırı", "Çorum",
    "Denizli", "Diyarbakır", "Düzce", "Edirne", "Elazığ", "Erzincan",
    "Erzurum", "Eskişehir", "Gaziantep", "Giresun", "Gümüşhane",
    "Hakkari", "Hatay", "Iğdır", "Isparta", "İstanbul", "İzmir",
    "Kahramanmaraş", "Karabük", "Karaman", "Kars", "Kastamonu",
    "Kayseri", "Kilis", "Kırıkkale", "Kırklareli", "Kırşehir",
    "Kocaeli", "Konya", "Kütahya", "Malatya", "Manisa", "Mardin",
    "Mersin", "Muğla", "Muş", "Nevşehir", "Niğde", "Ordu",
    "Osmaniye", "Rize", "Sakarya", "Samsun", "Şanlıurfa", "Siirt",
    "Sinop", "Şırnak", "Sivas", "Tekirdağ", "Tokat", "Trabzon",
    "Tunceli", "Uşak", "Van", "Yalova", "Yozgat", "Zonguldak"
]

// MARK: - CityPickerSheet (shared component)

struct CityPickerSheet: View {
    @Binding var selectedCity: String
    @State private var searchQuery = ""
    @Environment(\.dismiss) private var dismiss

    private var filteredCities: [String] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? TurkishCities : TurkishCities.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.gray)
                    TextField("Şehir ara...", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.vertical, 8)

                List(filteredCities, id: \.self) { city in
                    Button {
                        selectedCity = city
                        dismiss()
                    } label: {
                        HStack {
                            Text(city).foregroundColor(.primary)
                            Spacer()
                            if city == selectedCity {
                                Image(systemName: "checkmark").foregroundColor(.orange)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Şehir Seç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
            }
        }
    }
}
