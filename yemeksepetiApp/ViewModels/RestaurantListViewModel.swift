import Foundation
import Combine

// MARK: - RestaurantListViewModel
//
// Anasayfa restoran listesi için sayfalama + filtre ViewModel'i.
// AdminViewModel'deki restoran bölümüyle aynı yaklaşım:
//   • Combine pipeline → debounce (400ms) + filtre değişimlerinde otomatik reload
//   • Sunucu taraflı pagination (GET /restaurants/paged)
//   • prefetchIfNeeded → listeye yaklaşıldığında sıradaki sayfa çekilir
//   • Mutfak tipi seçenekleri API'dan (distinct-cuisines)

@MainActor
final class RestaurantListViewModel: ObservableObject {

    // MARK: - Output (read-only for views)

    @Published private(set) var restaurants: [Restaurant] = []
    @Published private(set) var total = 0
    @Published private(set) var hasMore = false
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var error: String?
    @Published private(set) var availableCuisines: [String] = []

    // MARK: - Filters (two-way binding from view)

    @Published var searchQuery = ""
    /// Dışarıdan HomeView'ın adres sistemi tarafından set edilir
    var cityFilter: String? {
        get { _cityFilter }
        set {
            guard newValue != _cityFilter else { return }
            _cityFilter = newValue
            // Manual trigger because @Published inside stored property won't auto-fire from external set
            cityFilterSubject.send(newValue)
        }
    }
    @Published var cuisineFilter: String?

    // MARK: - Private

    private let api: RestaurantAPIService
    private var cancellables = Set<AnyCancellable>()
    private var fetchTask: Task<Void, Never>?
    private var cuisineTask: Task<Void, Never>?

    private var offset = 0
    private let pageSize = 20
    private let prefetchThreshold = 5

    private var _cityFilter: String?
    private let cityFilterSubject = PassthroughSubject<String?, Never>()

    // MARK: - Init

    init(api: RestaurantAPIService) {
        self.api = api
        setupFilterPipeline()
    }

    // MARK: - Combine Pipeline

    private func setupFilterPipeline() {
        // Debounce yazma
        let debouncedSearch = $searchQuery
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }

        // Mutfak seçimi anında tetikler
        let cuisineChange = $cuisineFilter
            .dropFirst()
            .map { _ in () }

        // Şehir değişimi (dışarıdan)
        let cityChange = cityFilterSubject
            .map { _ in () }

        Publishers.Merge3(debouncedSearch, cuisineChange, cityChange)
            .sink { [weak self] in self?.reloadRestaurants() }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    /// Filtreleri koruyarak baştan yükler (pull-to-refresh / ilk açılış / filtre değişimi)
    func reloadRestaurants() {
        fetchTask?.cancel()
        offset      = 0
        restaurants = []
        hasMore     = false
        error       = nil
        _fetchPage()
        loadCuisineOptions()
    }

    /// Sıradaki sayfayı yükler — zaten yükleniyorsa / daha fazla yoksa çıkar
    func loadMoreRestaurants() {
        guard !isLoading, !isLoadingMore, hasMore else { return }
        _fetchPage()
    }

    /// ForEach currentIndex ile çağrılır — proaktif prefetch
    func prefetchIfNeeded(currentIndex: Int) {
        guard restaurants.count - currentIndex <= prefetchThreshold else { return }
        loadMoreRestaurants()
    }

    /// Mutfak filtresi seçeneklerini çeker (şehre göre daraltılmış)
    func loadCuisineOptions() {
        cuisineTask?.cancel()
        cuisineTask = Task { [weak self] in
            guard let self else { return }
            do {
                let list = try await self.api.fetchDistinctCuisines(city: self._cityFilter)
                guard !Task.isCancelled else { return }
                self.availableCuisines = list
            } catch {
                // Non-critical — sadece logla
            }
        }
    }

    // MARK: - Private Fetch

    private func _fetchPage() {
        let currentOffset = offset
        let isFirstPage   = currentOffset == 0

        if isFirstPage { isLoading = true } else { isLoadingMore = true }

        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.api.fetchActivePage(
                    offset:  currentOffset,
                    limit:   self.pageSize,
                    search:  self.searchQuery.trimmingCharacters(in: .whitespaces).nonEmptyOrNil,
                    city:    self._cityFilter,
                    cuisine: self.cuisineFilter
                )
                guard !Task.isCancelled else { return }

                if isFirstPage {
                    self.restaurants = result.restaurants
                } else {
                    let existing = Set(self.restaurants.map(\.id))
                    self.restaurants += result.restaurants.filter { !existing.contains($0.id) }
                }
                self.total   = result.total
                self.offset  = (result.nextOffset ?? (currentOffset + result.restaurants.count))
                self.hasMore = result.hasMore
                self.error   = nil
            } catch {
                guard !Task.isCancelled else { return }
                if isFirstPage { self.error = error.localizedDescription }
            }
            if isFirstPage { self.isLoading = false } else { self.isLoadingMore = false }
        }
    }
}

// MARK: - String helper

private extension String {
    var nonEmptyOrNil: String? { isEmpty ? nil : self }
}
