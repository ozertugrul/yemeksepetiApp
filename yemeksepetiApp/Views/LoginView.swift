import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var isSecured = true
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingRegistration = false

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 25) {
                // Logo
                VStack(spacing: 10) {
                    Image(systemName: "fork.knife.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .foregroundColor(.red)

                    Text("Yemeksepeti")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.red)
                }
                .padding(.bottom, 30)

                // Input Fields
                VStack(spacing: 15) {
                    TextField("E-posta", text: $email)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))

                    HStack {
                        if isSecured {
                            SecureField("Şifre", text: $password)
                        } else {
                            TextField("Şifre", text: $password)
                        }
                        Button { isSecured.toggle() } label: {
                            Image(systemName: isSecured ? "eye.slash" : "eye")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                }
                .padding(.horizontal)

                // Error Message
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Login Button
                Button(action: signIn) {
                    ZStack {
                        Text("Giriş Yap")
                            .font(.headline)
                            .foregroundColor(.white)
                            .opacity(isLoading ? 0 : 1)
                        if isLoading {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(isFormValid && !isLoading ? Color.red : Color.red.opacity(0.4))
                    .cornerRadius(10)
                    .shadow(color: .red.opacity(0.3), radius: 5, x: 0, y: 5)
                }
                .disabled(!isFormValid || isLoading)
                .padding(.horizontal)

                // Divider
                HStack {
                    Rectangle().frame(height: 1).foregroundColor(.gray.opacity(0.3))
                    Text("veya").font(.footnote).foregroundColor(.gray)
                    Rectangle().frame(height: 1).foregroundColor(.gray.opacity(0.3))
                }
                .padding(.horizontal)

                // Guest Button
                Button(action: signInAnonymously) {
                    Text("Misafir Olarak Devam Et")
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red, lineWidth: 1))
                }
                .disabled(isLoading)
                .padding(.horizontal)

                Spacer()

                // Register
                VStack(spacing: 5) {
                    Text("Hesabın yok mu?")
                        .font(.footnote)
                        .foregroundColor(.gray)
                    Button { showingRegistration = true } label: {
                        Text("Kayıt Ol")
                            .font(.headline)
                            .foregroundColor(.red)
                    }
                    .disabled(isLoading)
                }
                .padding(.bottom, 20)
            }
            .padding()
        }
        .sheet(isPresented: $showingRegistration) {
            RegisterView(viewModel: viewModel)
        }
    }

    // MARK: - Actions

    private func signIn() {
        errorMessage = ""
        isLoading = true
        viewModel.authService.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password) { result in
            isLoading = false
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
            // On success, AuthService sets isAuthenticated = true → MainView transitions automatically.
        }
    }

    private func signInAnonymously() {
        isLoading = true
        viewModel.authService.signInAnonymously { result in
            isLoading = false
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
    }
}

