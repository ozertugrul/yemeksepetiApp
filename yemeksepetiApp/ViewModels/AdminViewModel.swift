import Foundation
import Combine

/// Tek kaynak (single source of truth) — admin panelindeki tüm sekmelerin
/// veri, yükleme, hata ve filtre durumu burada yönetilir.
///
/// **Mimari:**
/// - `AdminDashboardView` bu VM'i `@StateObject` olarak oluşturur ve alt
///   ekranlara `@ObservedObject` olarak enjekte eder.
/// - Filtre property'leri `@Published var` ile view'lara binding sunar;
///   değişimler Combine pipeline'ı üzerinden otomatik reload tetikler.
/// - Tüm network çağrıları Task + cancellation destekli; hızlı filtre
///   değişimlerinde yarış koşulu (race condition) olmaz.
/// - Silme / güncelleme işlemleri network tamamlandıktan sonra yerel
///   koleksiyona optimistic uygulama yapar, gereksiz tam-reload önlenir.
@MainActor
final class AdminViewModel: ObservableObject {

    // MARK: - Users — Veri

    @Published private(set) var users: [AppUser] = []
    @Published private(set) var userTotal: Int = 0
    @Published private(set) var isLoadingUsers = false
    @Published private(set) var hasMoreUsers = false
    @Published private(set) var userError: String?

    // MARK: - Users — Filtreler (view binding)

    @Published var userSearchQuery = ""
    @Published var userRoleFilter: UserRole?
    @Published var userCityFilter: String?

    // MARK: - Restaurants — Veri

    @Published private(set) var restaurants: [Restaurant] = []
    @Published private(set) var restaurantTotal: Int = 0
    @Published private(set) var isLoadingRestaurants = false
    @Published private(set) var hasMoreRestaurants = false
    @Published private(set) var restaurantError: String?

    // MARK: - Restaurants — Filtreler (view binding)

    @Published var restaurantSearchQuery = ""
    @Published var restaurantCityFilter: String?
    @Published var restaurantCuisineFilter: String?
    @Published var restaurantActiveFilter: Bool?

    // MARK: - Stats

    @Published private(set) var stats: AdminStats?
    @Published private(set) var isLoadingStats = false
    @Published private(set) var statsError: String?

    // MARK: - Private

    private let api: AdminAPIService
    private var cancellables = Set<AnyCancellable>()

    private var userFetchTask: Task<Void, Never>?
    private var restaurantFetchTask: Task<Void, Never>?

    private var userOffset = 0
    private var restaurantOffset = 0
    private let pageSize = 50

    // MARK: - Init

    init(api: AdminAPIService) {
        self.api = api
        setupUserFilterPipeline()
        setupRestaurantFilterPipeline()
    }

    // MARK: - Combine Pipelines

    private func setupUserFilterPipeline() {
        // Arama metni debounce'lu (hızlı yazarken çok istek atılmaz)
        let debouncedSearch = $userSearchQuery
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }

        // Rol / şehir seçimi anında tetikler
        let roleChange = $userRoleFilter.dropFirst().map { _ in () }
        let cityChange = $userCityFilter.dropFirst().map { _ in () }

        Publishers.Merge3(debouncedSearch, roleChange, cityChange)
            .sink { [weak self] in self?.reloadUsers() }
            .store(in: &cancellables)
    }

    private func setupRestaurantFilterPipeline() {
        let debouncedSearch = $restaurantSearchQuery
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }

        let cityChange    = $restaurantCityFilter.dropFirst().map    { _ in () }
        let cuisineChange = $restaurantCuisineFilter.dropFirst().map { _ in () }
        let activeChange  = $restaurantActiveFilter.dropFirst().map  { _ in () }

        Publishers.Merge4(debouncedSearch, cityChange, cuisineChange, activeChange)
            .sink { [weak self] in self?.reloadRestaurants() }
            .store(in: &cancellables)
    }

    // MARK: - Users — Fetch

    /// Filtreleri koruyarak baştan yükler. Dışarıdan da çağrılabilir (pull-to-refresh, CRUD sonrası).
    func reloadUsers() {
        userFetchTask?.cancel()
        userOffset = 0
        users      = []
        hasMoreUsers = false
        userError  = nil
        _fetchUsersPage()
    }

    /// Sonraki sayfayı yükler; zaten yükleniyorsa veya daha fazla yoksa çıkar.
    func loadMoreUsers() {
        guard !isLoadingUsers, hasMoreUsers else { return }
        _fetchUsersPage()
    }

    private func _fetchUsersPage() {
        let offset = userOffset
        isLoadingUsers = true

        userFetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.api.fetchUsersPage(
                    offset: offset,
                    limit:  self.pageSize,
                    search: self.userSearchQuery.trimmedOrNil,
                    role:   self.userRoleFilter,
                    city:   self.userCityFilter
                )
                guard !Task.isCancelled else { return }

                if offset == 0 {
                    self.users = page.users
                } else {
                    let existing = Set(self.users.map(\.id))
                    self.users += page.users.filter { !existing.contains($0.id) }
                }
                self.userTotal   = page.total
                self.userOffset  = page.nextOffset ?? (offset + page.users.count)
                self.hasMoreUsers = page.hasMore
                self.userError   = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.userError = error.localizedDescription
            }
            self.isLoadingUsers = false
        }
    }

    // MARK: - Restaurants — Fetch

    func reloadRestaurants() {
        restaurantFetchTask?.cancel()
        restaurantOffset   = 0
        restaurants        = []
        hasMoreRestaurants = false
        restaurantError    = nil
        _fetchRestaurantsPage()
    }

    func loadMoreRestaurants() {
        guard !isLoadingRestaurants, hasMoreRestaurants else { return }
        _fetchRestaurantsPage()
    }

    private func _fetchRestaurantsPage() {
        let offset = restaurantOffset
        isLoadingRestaurants = true

        restaurantFetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.api.fetchRestaurantsPage(
                    offset:   offset,
                    limit:    self.pageSize,
                    search:   self.restaurantSearchQuery.trimmedOrNil,
                    city:     self.restaurantCityFilter,
                    cuisine:  self.restaurantCuisineFilter,
                    isActive: self.restaurantActiveFilter
                )
                guard !Task.isCancelled else { return }

                if offset == 0 {
                    self.restaurants = page.restaurants
                } else {
                    let existing = Set(self.restaurants.map(\.id))
                    self.restaurants += page.restaurants.filter { !existing.contains($0.id) }
                }
                self.restaurantTotal   = page.total
                self.restaurantOffset  = page.nextOffset ?? (offset + page.restaurants.count)
                self.hasMoreRestaurants = page.hasMore
                self.restaurantError   = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.restaurantError = error.localizedDescription
            }
            self.isLoadingRestaurants = false
        }
    }

    // MARK: - Stats — Fetch

    func loadStats(forceRefresh: Bool = false) {
        guard !isLoadingStats else { return }
        if stats != nil && !forceRefresh { return }
        isLoadingStats = true
        statsError = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                self.stats = try await self.api.fetchStats()
                self.statsError = nil
            } catch {
                self.statsError = error.localizedDescription
            }
            self.isLoadingStats = false
        }
    }

    // MARK: - User Actions (Optimistic Updates)

    func performUpdateUserRole(uid: String, role: UserRole) async throws {
        try await api.updateUserRole(uid: uid, role: role)
        _optimisticallyUpdateUser(uid: uid) {
            AppUser(id: $0.id, email: $0.email, role: role,
                    managedRestaurantId: $0.managedRestaurantId,
                    fullName: $0.fullName, phone: $0.phone, city: $0.city)
        }
    }

    func performDeleteUser(uid: String) async throws {
        try await api.deleteUser(uid: uid)
        users.removeAll { $0.id == uid }
        userTotal = max(0, userTotal - 1)
    }

    func performCreateUser(
        email: String, password: String,
        displayName: String?, role: UserRole
    ) async throws -> AppUser {
        let user = try await api.createUser(
            email: email, password: password,
            displayName: displayName, role: role
        )
        reloadUsers()
        return user
    }

    func performAssignManagedRestaurant(uid: String, restaurantId: String?) async throws {
        _ = try await api.assignManagedRestaurant(uid: uid, restaurantId: restaurantId)
        reloadUsers()
    }

    // MARK: - Restaurant Actions (Optimistic Updates)

    func performToggleRestaurantActive(id: String) async throws {
        let updated = try await api.toggleRestaurantActive(id: id)
        if let idx = restaurants.firstIndex(where: { $0.id == id }) {
            restaurants[idx] = updated
        }
    }

    func performDeleteRestaurant(id: String) async throws {
        try await api.deleteRestaurant(id: id)
        restaurants.removeAll { $0.id == id }
        restaurantTotal = max(0, restaurantTotal - 1)
    }

    // MARK: - Computed Filter Helpers

    /// Yüklü kullanıcılardan rol bazlı sayılar (filtre chip badge'leri için)
    var userRoleCounts: (users: Int, storeOwners: Int, admins: Int) {
        let u = users.filter { $0.role == .user }.count
        let s = users.filter { $0.role == .storeOwner }.count
        let a = users.filter { $0.role == .superAdmin }.count
        return (u, s, a)
    }

    /// Yüklü kullanıcılardaki benzersiz şehirler (şehir filtresi picker için)
    var userDistinctCities: [String] {
        Array(Set(users.compactMap(\.city).filter { !$0.isEmpty })).sorted()
    }

    /// Yüklü restoranlardan active/passive sayılar
    var restaurantActiveCounts: (active: Int, passive: Int) {
        let a = restaurants.filter(\.isActive).count
        return (a, restaurants.count - a)
    }

    var restaurantDistinctCities: [String] {
        Array(Set(restaurants.compactMap(\.city).filter { !$0.isEmpty })).sorted()
    }

    var restaurantDistinctCuisines: [String] {
        Array(Set(restaurants.map(\.cuisineType).filter { !$0.isEmpty })).sorted()
    }

    // MARK: - Private Helpers

    private func _optimisticallyUpdateUser(uid: String, transform: (AppUser) -> AppUser) {
        guard let idx = users.firstIndex(where: { $0.id == uid }) else { return }
        users[idx] = transform(users[idx])
    }
}

// MARK: - String extension

private extension String {
    var trimmedOrNil: String? {
        let s = trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}
