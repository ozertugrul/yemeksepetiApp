import Foundation
import Combine

// MARK: - Auth DTOs

private struct LoginRequest: Encodable {
    let email: String
    let password: String
}

private struct RegisterRequest: Encodable {
    let email: String
    let password: String
    let displayName: String?
}

private struct ChangePasswordRequest: Encodable {
    let currentPassword: String
    let newPassword: String
}

private struct ChangeEmailRequest: Encodable {
    let currentPassword: String
    let newEmail: String
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let userId: String
    let email: String
    let role: String
    let displayName: String?
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType   = "token_type"
        case userId      = "user_id"
        case email, role
        case displayName = "display_name"
    }
}

// MARK: - AuthService

class AuthService: ObservableObject {
    @Published var user: AppUser?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let userAPI = UserAPIService()
    private let guestIdPrefix = "guest-"
    private var apiUnauthorizedObserver: NSObjectProtocol?
    private var apiForbiddenObserver: NSObjectProtocol?

    init() {
        restoreSession()
        apiUnauthorizedObserver = NotificationCenter.default.addObserver(
            forName: .apiUnauthorized,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.signOut() }

        apiForbiddenObserver = NotificationCenter.default.addObserver(
            forName: .apiForbidden,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.refreshCurrentUser() }
    }

    deinit {
        if let o = apiUnauthorizedObserver { NotificationCenter.default.removeObserver(o) }
        if let o = apiForbiddenObserver    { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - Session Restore

    private func restoreSession() {
        guard KeychainHelper.loadToken() != nil else { return }
        Task {
            do {
                let profile = try await userAPI.fetchMyProfile()
                let profileId = profile.id
                let profileEmail = profile.email ?? ""
                let appUser = AppUser(
                    id: profileId,
                    email: profileEmail,
                    role: Self.mapAPIRole(profile.role),
                    managedRestaurantId: profile.managedRestaurantId,
                    fullName: profile.displayName,
                    phone: profile.phone,
                    city: profile.city
                )
                await MainActor.run { self.user = appUser }
            } catch {
                KeychainHelper.clearAll()
            }
        }
    }

    // MARK: - Sign In

    func signIn(email: String, password: String, completion: @escaping (Result<AppUser, Error>) -> Void) {
        isLoading = true
        Task {
            do {
                let tokenResp: TokenResponse = try await APIClient.shared.post(
                    TokenResponse.self, path: "/auth/login",
                    encodable: LoginRequest(email: email, password: password))
                KeychainHelper.saveToken(tokenResp.accessToken)
                let appUser = AppUser(
                    id: tokenResp.userId, email: tokenResp.email,
                    role: Self.mapAPIRole(tokenResp.role), fullName: tokenResp.displayName)
                await MainActor.run {
                    self.isLoading = false
                    self.user = appUser
                    completion(.success(appUser))
                }
                await fetchAndUpdateProfile()
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Register

    func register(email: String, password: String, displayName: String,
                  completion: @escaping (Result<AppUser, Error>) -> Void) {
        isLoading = true
        Task {
            do {
                let tokenResp: TokenResponse = try await APIClient.shared.post(
                    TokenResponse.self, path: "/auth/register",
                    encodable: RegisterRequest(email: email, password: password,
                                              displayName: displayName.isEmpty ? nil : displayName))
                KeychainHelper.saveToken(tokenResp.accessToken)
                let appUser = AppUser(
                    id: tokenResp.userId, email: tokenResp.email,
                    role: Self.mapAPIRole(tokenResp.role),
                    fullName: tokenResp.displayName ?? displayName)
                await MainActor.run {
                    self.isLoading = false
                    self.user = appUser
                    completion(.success(appUser))
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Sign Out

    func signOut() {
        KeychainHelper.clearAll()
        DispatchQueue.main.async { self.user = nil }
    }

    // MARK: - Profile

    func fetchUserProfileFromAPI(uid: String, completion: ((AppUser?) -> Void)? = nil) {
        Task { let r = await fetchAndUpdateProfile(); completion?(r) }
    }

    @discardableResult
    private func fetchAndUpdateProfile() async -> AppUser? {
        do {
            let profile = try await userAPI.fetchMyProfile()
            let profileId = profile.id
            let profileEmail = profile.email ?? self.user?.email ?? ""
            let appUser = AppUser(
                id: profileId,
                email: profileEmail,
                role: Self.mapAPIRole(profile.role),
                managedRestaurantId: profile.managedRestaurantId,
                fullName: profile.displayName,
                phone: profile.phone,
                city: profile.city
            )
            await MainActor.run { self.user = appUser }
            return appUser
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
            return nil
        }
    }

    // MARK: - Compatibility shims

    var currentUser: AppUser? { user }
    var userRole: UserRole { user?.role ?? .user }
    var isAuthenticated: Bool { user != nil }
    var isGuest: Bool { user?.id.hasPrefix(guestIdPrefix) == true }

    static func mapAPIRole(_ raw: String?) -> UserRole {
        switch raw {
        case "admin":      return .superAdmin
        case "storeOwner": return .storeOwner
        default:           return .user
        }
    }

    // MARK: - Admin stubs

    func fetchAllUsers(completion: @escaping ([AppUser]) -> Void) { completion([]) }
    func updateUserRole(uid: String, role: UserRole, completion: @escaping (Error?) -> Void) { completion(nil) }
    func deleteUser(uid: String, completion: @escaping (Error?) -> Void) { completion(nil) }

    func refreshCurrentUser() {
        guard user != nil else { return }
        Task { await fetchAndUpdateProfile() }
    }

    // MARK: - Change Email

    func updateEmail(newEmail: String, currentPassword: String, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                let tokenResp: TokenResponse = try await APIClient.shared.post(
                    TokenResponse.self, path: "/auth/change-email",
                    encodable: ChangeEmailRequest(currentPassword: currentPassword, newEmail: newEmail))
                KeychainHelper.saveToken(tokenResp.accessToken)
                await MainActor.run {
                    if let current = self.user {
                        self.user = AppUser(
                            id: current.id,
                            email: tokenResp.email,
                            role: current.role,
                            managedRestaurantId: current.managedRestaurantId,
                            fullName: current.fullName,
                            phone: current.phone,
                            city: current.city
                        )
                    }
                    completion(nil)
                }
            } catch {
                await MainActor.run { completion(error) }
            }
        }
    }

    // MARK: - Change Password

    func changePassword(currentPassword: String, newPassword: String, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await APIClient.shared.executeVoid(
                    method: "POST", path: "/auth/change-password",
                    body: try JSONEncoder().encode(
                        ChangePasswordRequest(currentPassword: currentPassword, newPassword: newPassword)))
                await MainActor.run { completion(nil) }
            } catch {
                await MainActor.run { completion(error) }
            }
        }
    }

    // MARK: - JWT iat → last sign-in

    func getLastSignInDate() -> Date? {
        guard let token = KeychainHelper.loadToken() else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = b64.count % 4
        if rem > 0 { b64 += String(repeating: "=", count: 4 - rem) }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let iat = json["iat"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: iat)
    }

    func signInAnonymously(completion: @escaping (Result<AppUser, Error>) -> Void) {
        isLoading = true
        Task { @MainActor in
            let guestUser = AppUser(
                id: "\(guestIdPrefix)\(UUID().uuidString)",
                email: "guest@yemeksepeti.local",
                role: .user,
                managedRestaurantId: nil,
                fullName: "Misafir"
            )
            self.user = guestUser
            self.isLoading = false
            completion(.success(guestUser))
        }
    }
}
