import SwiftUI

struct RegisterView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    
    // ── Registration step ────────────────────────────────────────────
    @State private var step: RegisterStep = .credentials
    
    // ── Credentials fields ───────────────────────────────────────────
    @State private var email = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSecured = true
    @State private var isSecuredConfirm = true
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    // ── City / Address step ──────────────────────────────────────────
    @State private var selectedCity = ""
    @State private var showingAddAddress = false
    @State private var citySaved = false
    
    private enum RegisterStep {
        case credentials
        case cityAddress
    }
    
    private var isEmailValid: Bool {
        let t = email.trimmingCharacters(in: .whitespaces)
        return t.count > 5 && t.contains("@") && t.contains(".")
    }

    private var isFormValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty &&
        isEmailValid &&
        password.count >= 6 &&
        password == confirmPassword
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                switch step {
                case .credentials:
                    credentialsStep
                        .transition(.asymmetric(insertion: .identity, removal: .move(edge: .leading)))
                case .cityAddress:
                    cityAddressStep
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .identity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: step)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .credentials {
                        Button("Kapat") { dismiss() }
                            .disabled(isLoading)
                    }
                }
            }
            .sheet(isPresented: $showingAddAddress, onDismiss: {
                // After adding address, proceed to finish
                if !selectedCity.isEmpty { dismiss() }
            }) {
                AddAddressView(viewModel: viewModel)
            }
        }
    }
    
    // MARK: - Step 1: Credentials
    
    private var credentialsStep: some View {
        VStack(spacing: 20) {
            Text("Yeni Hesap Oluştur")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.red)
                .padding(.bottom, 20)
            
            // Ad Soyad
            TextField("Ad Soyad", text: $displayName)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)

            // Email
            TextField("E-posta", text: $email)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            
            // Password
            ZStack(alignment: .trailing) {
                if isSecured {
                    SecureField("Şifre (en az 6 karakter)", text: $password)
                } else {
                    TextField("Şifre (en az 6 karakter)", text: $password)
                }
                Button(action: { isSecured.toggle() }) {
                    Image(systemName: isSecured ? "eye.slash" : "eye")
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            
            // Confirm Password
            ZStack(alignment: .trailing) {
                if isSecuredConfirm {
                    SecureField("Şifre Tekrar", text: $confirmPassword)
                } else {
                    TextField("Şifre Tekrar", text: $confirmPassword)
                }
                Button(action: { isSecuredConfirm.toggle() }) {
                    Image(systemName: isSecuredConfirm ? "eye.slash" : "eye")
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        confirmPassword.isEmpty ? Color.gray.opacity(0.3)
                            : (password == confirmPassword ? Color.green.opacity(0.6) : Color.red.opacity(0.6)),
                        lineWidth: 1
                    )
            )
            
            // Error message
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            
            // Register Button
            Button(action: {
                register()
            }) {
                ZStack {
                    Text("Kayıt Ol")
                        .font(.headline)
                        .foregroundColor(.white)
                        .opacity(isLoading ? 0 : 1)
                    
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(isFormValid && !isLoading ? Color.red : Color.red.opacity(0.4))
                .cornerRadius(10)
            }
            .disabled(!isFormValid || isLoading)
            .padding(.top)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Step 2: City & Address
    
    private var cityAddressStep: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 24) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.orange)
                
                VStack(spacing: 8) {
                    Text("Hoş geldin, \(displayName.components(separatedBy: " ").first ?? "")!")
                        .font(.title2).fontWeight(.bold)
                    Text("Size en yakın restoranları gösterebilmemiz için bulunduğunuz şehri seçin.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                // City selection
                Button {
                    // Inline city picker
                } label: {
                    HStack {
                        Image(systemName: "building.2.fill")
                            .foregroundColor(.orange)
                        Text(selectedCity.isEmpty ? "Şehir Seç" : selectedCity)
                            .foregroundColor(selectedCity.isEmpty ? .secondary : .primary)
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                
                // City list — filtered
                cityListView
                    .padding(.horizontal, 32)
                
                VStack(spacing: 12) {
                    // Continue with address
                    Button {
                        saveCityAndContinue(addAddress: true)
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Adres Ekle").fontWeight(.semibold)
                        }
                        .font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(selectedCity.isEmpty ? Color.orange.opacity(0.4) : Color.orange)
                        .cornerRadius(14)
                    }
                    .disabled(selectedCity.isEmpty)
                    
                    // Skip — just save city
                    Button {
                        saveCityAndContinue(addAddress: false)
                    } label: {
                        Text("Şimdilik Atla")
                            .font(.subheadline).fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    .disabled(selectedCity.isEmpty && !citySaved)
                }
                .padding(.horizontal, 32)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
    
    @State private var citySearch = ""
    
    private var cityListView: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.gray).font(.caption)
                TextField("Şehir ara...", text: $citySearch)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                if !citySearch.isEmpty {
                    Button { citySearch = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.gray).font(.caption)
                    }
                }
            }
            .padding(8)
            .background(Color(.systemGray5))
            .cornerRadius(8)
            
            let q = citySearch.trimmingCharacters(in: .whitespaces).lowercased()
            let filtered = q.isEmpty ? TurkishCities : TurkishCities.filter { $0.lowercased().contains(q) }
            
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered, id: \.self) { city in
                        Button {
                            selectedCity = city
                            citySearch = ""
                        } label: {
                            HStack {
                                Text(city)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Spacer()
                                if city == selectedCity {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.orange)
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 10)
                        }
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 180)
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
    
    // MARK: - Actions
    
    private func register() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedName  = displayName.trimmingCharacters(in: .whitespaces)
        
        guard !trimmedName.isEmpty else {
            errorMessage = "Lütfen adınızı ve soyadınızı girin."
            return
        }
        
        guard isEmailValid else {
            errorMessage = "Lütfen geçerli bir e-posta adresi girin."
            return
        }
        
        guard password.count >= 6 else {
            errorMessage = "Şifre en az 6 karakter olmalıdır."
            return
        }
        
        guard password == confirmPassword else {
            errorMessage = "Şifreler eşleşmiyor!"
            return
        }
        
        errorMessage = ""
        isLoading = true
        
        viewModel.authService.register(email: trimmedEmail, password: password, displayName: trimmedName) { result in
            self.isLoading = false
            switch result {
            case .success:
                // Move to city/address step instead of dismissing
                withAnimation { self.step = .cityAddress }
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    private func saveCityAndContinue(addAddress: Bool) {
        guard !selectedCity.isEmpty else { return }
        
        // Save city to user profile via API
        guard let uid = viewModel.authService.currentUser?.id else {
            if addAddress { showingAddAddress = true } else { dismiss() }
            return
        }
        
        viewModel.dataService.updateUserProfile(uid: uid, data: ["city": selectedCity]) { _ in
            viewModel.authService.refreshCurrentUser()
            citySaved = true
            if addAddress {
                showingAddAddress = true
            } else {
                dismiss()
            }
        }
    }
}
