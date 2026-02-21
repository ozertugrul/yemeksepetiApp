import FirebaseAuth
import FirebaseFirestore
import Foundation
import Combine

// MARK: - AuthError

enum AuthError: LocalizedError {
    case missingUID
    case profileNotFound

    var errorDescription: String? {
        switch self {
        case .missingUID:      return "Kullanıcı kimliği alınamadı. Lütfen tekrar deneyin."
        case .profileNotFound: return "Kullanıcı profili bulunamadı."
        }
    }
}

/// Simple error wrapper that carries a user-facing localized message.
struct FirebaseUserError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Firebase Error Mapper

/// Maps Firebase Auth error codes to user-friendly Turkish messages.
/// Also extracts the underlying error from Firebase's opaque internal error (code 17999).
func friendlyAuthErrorMessage(_ error: Error) -> String {
    let nsError = error as NSError

    // FIRAuthErrorCodeInternalError (17999) wraps the real reason in NSUnderlyingErrorKey
    if nsError.code == 17999 {
        let underlying = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)
            ?? (nsError.userInfo["NSUnderlyingError"] as? NSError)
        let detail = underlying?.localizedDescription ?? nsError.userInfo.description
        print("[AuthService] Firebase internal error detail: \(detail)")
        print("[AuthService] Full userInfo: \(nsError.userInfo)")
        // Most common cause: Email/Password sign-in method is disabled in Firebase Console
        return "Firebase Auth hatası (17999). Firebase Console → Authentication → Sign-in methods → Email/Password ve Anonymous seçeneklerini etkinleştirin."
    }

    switch nsError.code {
    case 17007: return "Bu e-posta adresi zaten kullanılıyor."
    case 17008: return "Geçersiz e-posta adresi."
    case 17009: return "Hatalı şifre. Lütfen tekrar deneyin."
    case 17011: return "Bu e-posta ile kayıtlı kullanıcı bulunamadı."
    case 17020: return "Ağ bağlantısı hatası. İnternet bağlantınızı kontrol edin."
    case 17026: return "Şifre çok zayıf. En az 6 karakter içermelidir."
    case 17034: return "E-posta doğrulanmamış. Lütfen gelen kutunuzu kontrol edin."
    default:
        print("[AuthService] Unhandled Firebase error \(nsError.code): \(nsError.localizedDescription)")
        return nsError.localizedDescription
    }
}

// MARK: - AuthService

final class AuthService: ObservableObject {

    // MARK: Published State
    @Published var currentUser: AppUser?
    @Published var isAuthenticated = false
    @Published var userRole: UserRole = .user

    /// True when the Firebase Auth session exists but there is no registered
    /// Firestore profile — i.e. the user signed in anonymously (guest mode).
    var isGuest: Bool { isAuthenticated && currentUser == nil }

    // MARK: Private
    private let db = Firestore.firestore()
    private let usersCollection = "users"
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    // MARK: Init / Deinit

    init() {
        // Firebase fires this immediately on init with the current user (or nil).
        // It also fires again on every login/logout — single source of truth for session state.
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            guard let self else { return }
            if let firebaseUser {
                self.fetchUserProfile(uid: firebaseUser.uid)
            } else {
                self.clearSession()
            }
        }
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    // MARK: - Sign In

    /// Authenticates with Firebase Auth then loads the Firestore user profile.
    func signIn(email: String, password: String, completion: @escaping (Result<AppUser, Error>) -> Void) {
        // ── DEV SHORTCUT ─────────────────────────────────────────────────────────
        // "a" / "a" → super-admin session. Signs in anonymously to get a real
        // Firebase Auth token (required for Firestore security rules), then writes
        // a superAdmin profile document so the auth state listener loads it correctly.
        // Remove before releasing to production.
        if email == "a" && password == "a" {
            Auth.auth().signInAnonymously { [weak self] result, anonError in
                guard let self else { return }
                if let anonError {
                    print("[AuthService] DEV SHORTCUT: anonymous sign-in failed: \(anonError.localizedDescription)")
                    print("[AuthService] DEV SHORTCUT: Enable Anonymous sign-in in Firebase Console → Authentication → Sign-in methods")
                }
                let uid = result?.user.uid ?? "dev_admin_id"
                let devAdmin = AppUser(id: uid, email: "admin@yemeksepeti.com",
                                      role: .superAdmin, managedRestaurantId: nil)
                // Write doc so auth-state listener always loads superAdmin role
                self.saveUserDocument(devAdmin) { _ in }
                DispatchQueue.main.async {
                    self.applySession(devAdmin)
                    completion(.success(devAdmin))
                }
            }
            return
        }

        // "b" / "b" → instant store-owner session (dev shortcut)
        if email == "b" && password == "b" {
            Auth.auth().signInAnonymously { [weak self] result, anonError in
                guard let self else { return }
                if let anonError {
                    print("[AuthService] DEV SHORTCUT b: anonymous sign-in failed: \(anonError.localizedDescription)")
                }
                let uid = result?.user.uid ?? "dev_owner_id"
                let devOwner = AppUser(id: uid, email: "owner@yemeksepeti.com",
                                      role: .storeOwner, managedRestaurantId: nil)
                self.saveUserDocument(devOwner) { _ in }
                DispatchQueue.main.async {
                    self.applySession(devOwner)
                    completion(.success(devOwner))
                }
            }
            return
        }
        // ─────────────────────────────────────────────────────────────────────────

        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            guard let self else { return }
            if let error {
                let msg = friendlyAuthErrorMessage(error)
                print("[AuthService] signIn failed: \(msg)")
                DispatchQueue.main.async { completion(.failure(FirebaseUserError(message: msg))) }
                return
            }
            guard let uid = result?.user.uid else {
                DispatchQueue.main.async { completion(.failure(AuthError.missingUID)) }
                return
            }
            self.fetchUserProfile(uid: uid, completion: completion)
        }
    }
    
    // MARK: - Register

    /// Creates a Firebase Auth account and persists a Firestore user document.
    func register(email: String, password: String, completion: @escaping (Result<AppUser, Error>) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            guard let self else { return }
            if let error {
                let msg = friendlyAuthErrorMessage(error)
                print("[AuthService] register failed: \(msg)")
                DispatchQueue.main.async { completion(.failure(FirebaseUserError(message: msg))) }
                return
            }
            guard let uid = result?.user.uid else {
                DispatchQueue.main.async { completion(.failure(AuthError.missingUID)) }
                return
            }
            let newUser = AppUser(id: uid, email: email, role: .user, managedRestaurantId: nil)
            self.saveUserDocument(newUser, completion: completion)
        }
    }
    
    // MARK: - Anonymous Sign-In

    /// Signs the user in anonymously. Auth state listener updates published state.
    func signInAnonymously(completion: @escaping (Result<Void, Error>) -> Void = { _ in }) {
        Auth.auth().signInAnonymously { _, error in
            if let error {
                let msg = friendlyAuthErrorMessage(error)
                print("[AuthService] signInAnonymously failed: \(msg)")
                DispatchQueue.main.async { completion(.failure(FirebaseUserError(message: msg))) }
            } else {
                DispatchQueue.main.async { completion(.success(())) }
                // authStateListener fires → isAuthenticated = true
            }
        }
    }

    // MARK: - Sign Out

    func signOut() {
        // Always clear session immediately — ensures dev shortcut (non-Firebase) sessions
        // also log out correctly, since the auth listener won't fire for them.
        clearSession()
        do {
            try Auth.auth().signOut()
        } catch {
            print("[AuthService] signOut error: \(error.localizedDescription)")
        }
    }

    // MARK: - Admin: Fetch All Users

    /// Returns every user document from Firestore, sorted by email.
    /// Uses manual dictionary decoding as a fallback for robustness.
    func fetchAllUsers(completion: @escaping ([AppUser], String?) -> Void) {
        db.collection(usersCollection).getDocuments { snapshot, error in
            if let error {
                let nsErr = error as NSError
                let msg: String
                if nsErr.code == 7 {
                    msg = "Firestore erişim engellendi. Firebase Console → Firestore → Rules kısmını kontrol edin."
                } else {
                    msg = error.localizedDescription
                }
                print("[AuthService] fetchAllUsers error (code \(nsErr.code)): \(error.localizedDescription)")
                DispatchQueue.main.async { completion([], msg) }
                return
            }
            guard let documents = snapshot?.documents else {
                DispatchQueue.main.async { completion([], nil) }
                return
            }
            // Try Codable decode first; fall back to manual dict decode
            let users: [AppUser] = documents.compactMap { doc in
                if let user = try? doc.data(as: AppUser.self) { return user }
                let data = doc.data()
                guard let email = data["email"] as? String,
                      let roleRaw = data["role"] as? String,
                      let role = UserRole(rawValue: roleRaw) else {
                    print("[AuthService] fetchAllUsers: cannot decode doc \(doc.documentID) data=\(data)")
                    return nil
                }
                let id = (data["id"] as? String) ?? doc.documentID
                let managedRestaurantId = data["managedRestaurantId"] as? String
                return AppUser(id: id, email: email, role: role, managedRestaurantId: managedRestaurantId)
            }
            print("[AuthService] fetchAllUsers: decoded \(users.count) of \(documents.count) docs")
            DispatchQueue.main.async { completion(users.sorted { $0.email < $1.email }, nil) }
        }
    }

    // MARK: - Admin: Search Users (client-side; no Firestore composite index needed)

    func searchUsers(emailQuery: String, completion: @escaping ([AppUser]) -> Void) {
        fetchAllUsers { users, _ in
            let q = emailQuery.trimmingCharacters(in: .whitespaces).lowercased()
            let result = q.isEmpty ? users : users.filter { $0.email.lowercased().contains(q) }
            completion(result)
        }
    }

    // MARK: - Admin: Update Role

    func updateUserRole(uid: String, role: UserRole, completion: @escaping (Error?) -> Void) {
        db.collection(usersCollection).document(uid)
            .updateData(["role": role.rawValue]) { error in
                DispatchQueue.main.async { completion(error) }
            }
    }

    // MARK: - Admin: Delete (ban) User

    /// Deletes the Firestore document. Without a profile the user cannot access gated content.
    func deleteUser(uid: String, completion: @escaping (Error?) -> Void) {
        db.collection(usersCollection).document(uid).delete { error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    // MARK: - Profile Management

    /// Re-fetches the current user's Firestore profile and refreshes published state.
    func refreshCurrentUser() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        fetchUserProfile(uid: uid)
    }

    /// Returns the last sign-in date from Firebase Auth metadata.
    func getLastSignInDate() -> Date? {
        Auth.auth().currentUser?.metadata.lastSignInDate
    }

    /// Updates the authenticated user's email address (requires re-authentication).
    func updateEmail(newEmail: String, currentPassword: String, completion: @escaping (Error?) -> Void) {
        guard let user = Auth.auth().currentUser, let email = user.email else {
            completion(FirebaseUserError(message: "Oturum bulunamadı.")); return
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
        user.reauthenticate(with: credential) { [weak self] _, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { completion(FirebaseUserError(message: friendlyAuthErrorMessage(error))) }
                return
            }
            user.updateEmail(to: newEmail) { error in
                if let error {
                    DispatchQueue.main.async { completion(FirebaseUserError(message: friendlyAuthErrorMessage(error))) }
                    return
                }
                self.db.collection(self.usersCollection).document(user.uid)
                    .updateData(["email": newEmail]) { err in
                        DispatchQueue.main.async {
                            completion(err)
                            if err == nil { self.refreshCurrentUser() }
                        }
                    }
            }
        }
    }

    /// Changes the authenticated user's password (requires re-authentication).
    func changePassword(currentPassword: String, newPassword: String, completion: @escaping (Error?) -> Void) {
        guard let user = Auth.auth().currentUser, let email = user.email else {
            completion(FirebaseUserError(message: "Oturum bulunamadı.")); return
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
        user.reauthenticate(with: credential) { _, error in
            if let error {
                DispatchQueue.main.async { completion(FirebaseUserError(message: friendlyAuthErrorMessage(error))) }
                return
            }
            user.updatePassword(to: newPassword) { error in
                DispatchQueue.main.async {
                    if let error { completion(FirebaseUserError(message: friendlyAuthErrorMessage(error))) }
                    else { completion(nil) }
                }
            }
        }
    }
}

// MARK: - Private Helpers

private extension AuthService {

    /// Persists a new AppUser to Firestore and applies the session on success.
    func saveUserDocument(_ user: AppUser, completion: @escaping (Result<AppUser, Error>) -> Void) {
        do {
            try db.collection(usersCollection).document(user.id).setData(from: user) { [weak self] error in
                guard let self else { return }
                DispatchQueue.main.async {
                    if let error {
                        completion(.failure(error))
                    } else {
                        self.applySession(user)
                        completion(.success(user))
                    }
                }
            }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }

    /// Loads the Firestore profile for a UID and updates published state.
    func fetchUserProfile(uid: String, completion: ((Result<AppUser, Error>) -> Void)? = nil) {
        db.collection(usersCollection).document(uid).getDocument { [weak self] document, error in
            guard let self else { return }
            if let error {
                print("[AuthService] fetchUserProfile error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion?(.failure(error)) }
                return
            }
            guard let document, document.exists,
                  let user = try? document.data(as: AppUser.self) else {
                // Auth account exists but no Firestore doc (e.g. anonymous user)
                DispatchQueue.main.async {
                    self.isAuthenticated = true
                    self.userRole = .user
                    completion?(.failure(AuthError.profileNotFound))
                }
                return
            }
            DispatchQueue.main.async {
                self.applySession(user)
                completion?(.success(user))
            }
        }
    }

    /// Applies authenticated state to all published properties. Must run on main thread.
    func applySession(_ user: AppUser) {
        currentUser = user
        userRole    = user.role
        isAuthenticated = true
    }

    /// Resets all session state. Must run on main thread.
    func clearSession() {
        DispatchQueue.main.async {
            self.currentUser    = nil
            self.userRole       = .user
            self.isAuthenticated = false
        }
    }
}
