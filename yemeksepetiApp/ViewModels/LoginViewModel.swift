import Foundation
import Combine

/// Thin view model wrapping AuthService for login/register screens.
/// Views can alternatively call authService directly via AppViewModel.
final class LoginViewModel: ObservableObject {

    @Published var email = ""
    @Published var password = ""
    @Published var errorMessage = ""
    @Published var isLoading = false

    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    // MARK: - Login

    func login(completion: @escaping (Result<AppUser, Error>) -> Void) {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !password.isEmpty else {
            errorMessage = "E-posta ve şifre boş bırakılamaz."
            return
        }
        isLoading = true
        errorMessage = ""
        authService.signIn(email: trimmed, password: password) { [weak self] result in
            guard let self else { return }
            self.isLoading = false
            if case .failure(let error) = result {
                self.errorMessage = error.localizedDescription
            }
            completion(result)
        }
    }

    func login() {
        login { _ in }
    }

    // MARK: - Register

    func register(confirmPassword: String, completion: @escaping (Result<AppUser, Error>) -> Void) {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorMessage = "Lütfen geçerli bir e-posta girin."; return }
        guard password.count >= 6   else { errorMessage = "Şifre en az 6 karakter olmalıdır.";  return }
        guard password == confirmPassword else { errorMessage = "Şifreler eşleşmiyor!";           return }

        isLoading = true
        errorMessage = ""
        authService.register(email: trimmed, password: password, displayName: "") { [weak self] result in
            guard let self else { return }
            self.isLoading = false
            if case .failure(let error) = result {
                self.errorMessage = error.localizedDescription
            }
            completion(result)
        }
    }
}
