import SwiftUI

// MARK: - CreateCouponView

struct CreateCouponView: View {
    let restaurantId: String
    let restaurantName: String
    let restaurantCity: String?
    let createdBy: String
    let couponService: CouponService
    let existingCoupon: Coupon?
    let onDone: (Coupon) -> Void

    @Environment(\.dismiss) private var dismiss

    // Form fields
    @State private var code: String = ""
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var discountType: DiscountType = .percentage
    @State private var discountValue: String = ""
    @State private var maxDiscountAmount: String = ""
    @State private var minCartTotal: String = ""
    @State private var maxTotalUsage: String = ""
    @State private var maxUsagePerUser: String = ""
    @State private var isPublic: Bool = false
    @State private var hasExpiry: Bool = false
    @State private var expiresAt: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var isActive: Bool = true

    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isEditing: Bool { existingCoupon != nil }

    var body: some View {
        NavigationView {
            Form {
                // ── Temel Bilgiler ─────────────────────────────────────
                Section("Kupon Bilgileri") {
                    HStack {
                        Text("Kod")
                        Spacer()
                        TextField("YEMEK20", text: $code)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onChange(of: code) { newValue in code = newValue.uppercased() }
                    }
                    HStack {
                        Text("Başlık")
                        Spacer()
                        TextField("Açıklayıcı başlık", text: $title)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Açıklama")
                        Spacer()
                        TextField("İsteğe bağlı", text: $description)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // ── İndirim ───────────────────────────────────────────
                Section("İndirim") {
                    Picker("İndirim Türü", selection: $discountType) {
                        ForEach(DiscountType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    HStack {
                        Text(discountType == .percentage ? "Yüzde (%)" : "Tutar (₺)")
                        Spacer()
                        TextField("0", text: $discountValue)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    if discountType == .percentage {
                        HStack {
                            Text("Maksimum İndirim (₺)")
                            Spacer()
                            TextField("Yok", text: $maxDiscountAmount)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                        }
                    }
                }

                // ── Koşullar ──────────────────────────────────────────
                Section("Koşullar (İsteğe Bağlı)") {
                    HStack {
                        Text("Min. Sepet Tutarı (₺)")
                        Spacer()
                        TextField("Yok", text: $minCartTotal)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("Toplam Kullanım Limiti")
                        Spacer()
                        TextField("Sınırsız", text: $maxTotalUsage)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                    HStack {
                        Text("Kullanıcı Başına Limit")
                        Spacer()
                        TextField("Sınırsız", text: $maxUsagePerUser)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                }

                // ── Görünürlük ────────────────────────────────────────
                Section("Görünürlük") {
                    Toggle("Herkese Açık", isOn: $isPublic)
                    if isPublic, let city = restaurantCity, !city.isEmpty {
                        HStack {
                            Text("Şehir")
                            Spacer()
                            Text(city)
                                .foregroundColor(.secondary)
                        }
                    }
                    Toggle("Aktif", isOn: $isActive)
                }

                // ── Son Kullanma Tarihi ────────────────────────────────
                Section("Son Kullanma Tarihi") {
                    Toggle("Son kullanma tarihi ekle", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Tarih", selection: $expiresAt, in: Date()..., displayedComponents: .date)
                    }
                }

                // ── Hata Mesajı ───────────────────────────────────────
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(isEditing ? "Kuponu Düzenle" : "Yeni Kupon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Text(isSaving ? "Kaydediliyor..." : "Kaydet").fontWeight(.semibold)
                    }
                    .disabled(isSaving || code.isEmpty || title.isEmpty || discountValue.isEmpty)
                }
            }
            .onAppear { prefillIfEditing() }
        }
    }

    // MARK: - Pre-fill for Edit

    private func prefillIfEditing() {
        guard let c = existingCoupon else { return }
        code            = c.code
        title           = c.title
        description     = c.description
        discountType    = c.discountType
        discountValue   = String(format: "%g", c.discountValue)
        maxDiscountAmount = c.maxDiscountAmount.map { String(format: "%g", $0) } ?? ""
        minCartTotal    = c.minCartTotal.map { String(format: "%g", $0) } ?? ""
        maxTotalUsage   = c.maxTotalUsage.map { "\($0)" } ?? ""
        maxUsagePerUser = c.maxUsagePerUser.map { "\($0)" } ?? ""
        isPublic        = c.isPublic
        isActive        = c.isActive
        hasExpiry       = c.expiresAt != nil
        if let exp = c.expiresAt { expiresAt = exp }
    }

    // MARK: - Save

    private func save() {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            errorMessage = "Kupon kodu boş olamaz."; return
        }
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Kupon başlığı boş olamaz."; return
        }

        guard let dv = parseDouble(discountValue), dv > 0 else {
            errorMessage = "Geçerli bir indirim değeri girin."; return
        }

        if discountType == .percentage, dv > 100 {
            errorMessage = "Yüzde indirim 100'den büyük olamaz."; return
        }

        if !maxDiscountAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           parseDouble(maxDiscountAmount) == nil {
            errorMessage = "Maksimum indirim alanı geçerli bir sayı olmalı."; return
        }
        if !minCartTotal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           parseDouble(minCartTotal) == nil {
            errorMessage = "Minimum sepet tutarı geçerli bir sayı olmalı."; return
        }
        if !maxTotalUsage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           Int(maxTotalUsage.trimmingCharacters(in: .whitespacesAndNewlines)) == nil {
            errorMessage = "Toplam kullanım limiti tam sayı olmalı."; return
        }
        if !maxUsagePerUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           Int(maxUsagePerUser.trimmingCharacters(in: .whitespacesAndNewlines)) == nil {
            errorMessage = "Kullanıcı başına limit tam sayı olmalı."; return
        }

        isSaving = true
        errorMessage = nil

        var coupon = existingCoupon ?? Coupon(
            code: "",
            title: "",
            discountType: .percentage,
            discountValue: 0,
            createdBy: createdBy
        )
        coupon.code             = trimmedCode
        coupon.title            = trimmedTitle
        coupon.description      = description.trimmingCharacters(in: .whitespaces)
        coupon.restaurantId     = restaurantId
        coupon.restaurantName   = restaurantName
        coupon.discountType     = discountType
        coupon.discountValue    = dv
        coupon.maxDiscountAmount = parseDouble(maxDiscountAmount)
        coupon.minCartTotal     = parseDouble(minCartTotal)
        coupon.maxTotalUsage    = Int(maxTotalUsage.trimmingCharacters(in: .whitespacesAndNewlines))
        coupon.maxUsagePerUser  = Int(maxUsagePerUser.trimmingCharacters(in: .whitespacesAndNewlines))
        coupon.isPublic         = isPublic
        coupon.city             = restaurantCity
        coupon.isActive         = isActive
        coupon.expiresAt        = hasExpiry ? expiresAt : nil
        if !isEditing { coupon.createdBy = createdBy; coupon.createdAt = Date() }

        if isEditing {
            couponService.updateCoupon(coupon) { error in
                isSaving = false
                if let error { errorMessage = mapCouponError(error) }
                else { onDone(coupon); dismiss() }
            }
        } else {
            couponService.createCoupon(coupon) { error in
                isSaving = false
                if let error { errorMessage = mapCouponError(error) }
                else { onDone(coupon); dismiss() }
            }
        }
    }

    private func parseDouble(_ raw: String) -> Double? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    private func mapCouponError(_ error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .serverError(_, let message) where !message.isEmpty:
                return message
            default:
                return api.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
