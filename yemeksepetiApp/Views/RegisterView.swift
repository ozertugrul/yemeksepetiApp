import SwiftUI

struct RegisterView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSecured = true
    @State private var isSecuredConfirm = true
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 6 &&
        password == confirmPassword
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Yeni Hesap Oluştur")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                    .padding(.bottom, 20)
                
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                        .disabled(isLoading)
                }
            }
        }
    }
    
    private func register() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        
        guard !trimmedEmail.isEmpty else {
            errorMessage = "Lütfen geçerli bir e-posta girin."
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
        
        viewModel.authService.register(email: trimmedEmail, password: password) { result in
            // AuthService guarantees main thread delivery
            self.isLoading = false
            switch result {
            case .success:
                self.dismiss()
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
