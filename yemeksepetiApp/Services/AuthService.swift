import Foundation
import FirebaseAuth
import Combine

// MARK: - AuthService (FirebaseFirestore fully removed)

class AuthService: ObservableObject {
    @Published var user: AppUser?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let userAPI = UserAPIService()
    private var cancellables = Set<AnyCancellable>()

    init() {
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            guard let self else { return }
            if let firebaseUser {
                self.fetchUserProfileFromAPI(uid: firebaseUser.uid)
            } else {
                DispatchQueue.main.async { self.user = nil }
            }
        }
    }

    // MARK: - Sign In

    func signIn(email: String, password: String, completion: @escaping (Result<AppUser, Error>) -> Void) {
        isLoading = true
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    completion(.failure(error))
                }
                return
            }
            guard let firebaseUser = result?.user else { return }
            self.fetchUserProfileFromAPI(uid: firebaseUser.uid) { appUser in
                DispatchQueue.main.async {
                    self.isLoading = false
                    if let appUser { completion(.success(appUser)) }
                    else {
                        completion(.failure(NSError(domain: "AuthService", code: -1,
                                                    userInfo: [NSLocalizedDescriptionKey: "Profil alınamadı"])))
                    }
                }
            }
        }
    }

    // MARK: - Register

    func register(email: String, password: String, displayName: String, completion: @escaping (Result<AppUser, Error>) -> Void) {
        isLoading = true
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    completion(.failure(error))
                }
                return
            }
            guard let firebaseUser = result?.user else { return }

            // Set Firebase display name
            let changeRequest = firebaseUser.createProfileChangeRequest()
            changeRequest.displayName = displayName
            changeRequest.commitChanges(completion: nil)

            // Fetch from backend — GET /users/me auto-creates the user row
            self.fetchUserProfileFromAPI(uid: firebaseUser.uid) { appUser in
                DispatchQueue.main.async {
                    self.isLoading = false
                    if let appUser { completion(.success(appUser)) }
                    else {
                        completion(.failure(NSError(domain: "AuthService", code: -2,
                                                    userInfo: [NSLocalizedDescriptionKey: "Profil oluşturulamadı"])))
                    }
                }
            }
        }
    }

    // MARK: - Sign Out

    func signOut() {
        try? Auth.auth().signOut()
        DispatchQueue.main.async { self.user = nil }
    }

    // MARK: - Fetch Profile from SQL API

    func fetchUserProfileFromAPI(uid: String, completion: ((AppUser?) -> Void)? = nil) {
        Task {
            do {
                let profile = try await userAPI.fetchMyProfile()
                let appUser = AppUser(
                    id: uid,
                    email: profile.email ?? "",
                    role: Self.mapAPIRole(profile.role),
                    managedRestaurantId: profile.managedRestaurantId,
                    fullName: profile.displayName,
                    phone: profile.phone,
                    city: profile.city
                )
                DispatchQueue.main.async {
                    self.user = appUser
                    completion?(appUser)
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    completion?(nil)
                }
            }
        }
    }

    // MARK: - Compatibility shims (views still use currentUser / userRole)

    /// Alias for `user` — keeps all existing view references working.
    var currentUser: AppUser? { user }

    /// Convenience role accessor used by MainView and other views.
    var userRole: UserRole { user?.role ?? .user }

    /// True when a user is signed in.
    var isAuthenticated: Bool { user != nil }

    /// True when signed in anonymously (guest).
    var isGuest: Bool { Auth.auth().currentUser?.isAnonymous ?? false }

    // MARK: - Role Mapping

    static func mapAPIRole(_ raw: String?) -> UserRole {
        switch raw {
        case "admin":      return .superAdmin
        case "storeOwner": return .storeOwner
        default:           return .user
        }
    }

    // MARK: - Admin stubs (routed via AppViewModel → AdminAPIService)

    func fetchAllUsers(completion: @escaping ([AppUser]) -> Void) {
        completion([])
    }

    func updateUserRole(uid: String, role: UserRole, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    func deleteUser(uid: String, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    // MARK: - Firebase Auth helpers

    func refreshCurrentUser() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        fetchUserProfileFromAPI(uid: uid)
    }

    func updateEmail(newEmail: String, currentPassword: String, completion: @escaping (Error?) -> Void) {
        guard let firebaseUser = Auth.auth().currentUser,
              let email = firebaseUser.email else {
            completion(NSError(domain: "AuthService", code: -10,
                               userInfo: [NSLocalizedDescriptionKey: "Kullanıcı bulunamadı"]))
            return
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
        firebaseUser.reauthenticate(with: credential) { _, error in
            if let error { completion(error); return }
            firebaseUser.updateEmail(to: newEmail) { err in completion(err) }
        }
    }

    func changePassword(currentPassword: String, newPassword: String, completion: @escaping (Error?) -> Void) {
        guard let firebaseUser = Auth.auth().currentUser,
              let email = firebaseUser.email else {
            completion(NSError(domain: "AuthService", code: -11,
                               userInfo: [NSLocalizedDescriptionKey: "Kullanıcı bulunamadı"]))
            return
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
        firebaseUser.reauthenticate(with: credential) { _, error in
            if let error { completion(error); return }
            firebaseUser.updatePassword(to: newPassword) { err in completion(err) }
        }
    }

    func getLastSignInDate() -> Date? {
        Auth.auth().currentUser?.metadata.lastSignInDate
    }

    func signInAnonymously(completion: @escaping (Result<AppUser, Error>) -> Void) {
        Auth.auth().signInAnonymously { [weak self] result, error in
            guard let self else { return }
            if let error { completion(.failure(error)); return }
            guard let firebaseUser = result?.user else { return }
            let appUser = AppUser(
                id: firebaseUser.uid,
                email: "Misafir",
                role: .user
            )
            DispatchQueue.main.async {
                self.user = appUser
                completion(.success(appUser))
            }
        }
    }
}
