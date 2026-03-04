import Foundation
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var storeResults: [SearchResultItem] = []
    @Published private(set) var menuResults: [SearchResultItem] = []
    @Published private(set) var similarMenuResults: [SearchResultItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isAwaitingSearch = false
    @Published private(set) var hasCompletedSearch = false
    @Published private(set) var error: String?
    @Published private(set) var recentSearches: [String] = []
    @Published private(set) var cityFilter: String?

    private var offset = 0
    private let pageSize = 20
    private let minQueryLength = 2
    private(set) var hasMore = false

    private let service: SearchServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private var lastRequestKey: RequestKey?

    private struct RequestKey: Hashable {
        let query: String
        let city: String?
        let offset: Int
        let limit: Int
    }

    init(service: SearchServiceProtocol = APISearchService()) {
        self.service = service
        setupPipeline()
    }

    private func setupPipeline() {
        $query
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .handleEvents(receiveOutput: { [weak self] value in
                guard let self else { return }
                if value.count >= self.minQueryLength {
                    self.isAwaitingSearch = true
                    self.hasCompletedSearch = false
                } else {
                    self.isAwaitingSearch = false
                    self.hasCompletedSearch = false
                }
            })
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] value in
                self?.search(reset: true, query: value)
            }
            .store(in: &cancellables)
    }

    func search(reset: Bool, query: String? = nil) {
        let q = (query ?? self.query).trimmingCharacters(in: .whitespacesAndNewlines)

        searchTask?.cancel()

        guard !q.isEmpty else {
            storeResults = []
            menuResults = []
            similarMenuResults = []
            hasMore = false
            offset = 0
            error = nil
            isAwaitingSearch = false
            hasCompletedSearch = false
            lastRequestKey = nil
            return
        }

        guard q.count >= minQueryLength else {
            storeResults = []
            menuResults = []
            similarMenuResults = []
            hasMore = false
            offset = 0
            error = nil
            isAwaitingSearch = false
            hasCompletedSearch = false
            lastRequestKey = nil
            return
        }

        if reset {
            offset = 0
        }

        let requestKey = RequestKey(
            query: q.lowercased(),
            city: cityFilter?.lowercased(),
            offset: offset,
            limit: pageSize
        )
        if requestKey == lastRequestKey {
            return
        }
        lastRequestKey = requestKey

        searchTask = Task { [weak self] in
            guard let self else { return }
            self.isAwaitingSearch = false
            self.isLoading = true
            defer { self.isLoading = false }

            do {
                let response = try await self.service.search(
                    query: q,
                    city: self.cityFilter,
                    offset: self.offset,
                    limit: self.pageSize
                )
                guard !Task.isCancelled else { return }

                if reset {
                    self.storeResults = response.stores
                    self.menuResults = response.menuItems
                    self.similarMenuResults = response.similarMenuItems
                } else {
                    let existingStoreIds = Set(self.storeResults.map(\.id))
                    let existingMenuIds = Set(self.menuResults.map(\.id))
                    let existingSimilarIds = Set(self.similarMenuResults.map(\.id))

                    self.storeResults += response.stores.filter { !existingStoreIds.contains($0.id) }
                    self.menuResults += response.menuItems.filter { !existingMenuIds.contains($0.id) }
                    self.similarMenuResults += response.similarMenuItems.filter { !existingSimilarIds.contains($0.id) }
                }

                self.hasMore = response.hasMore
                self.offset = response.nextOffset ?? (self.offset + self.pageSize)
                self.error = nil
                self.hasCompletedSearch = true
            } catch {
                guard !Task.isCancelled else { return }
                self.lastRequestKey = nil
                self.error = error.localizedDescription
                self.hasCompletedSearch = true
            }
        }
    }

    func loadMoreIfNeeded(currentItem: SearchResultItem) {
        guard hasMore, !isLoading else { return }

        let shouldLoadMore =
            isNearEnd(currentItem, in: storeResults) ||
            isNearEnd(currentItem, in: menuResults) ||
            isNearEnd(currentItem, in: similarMenuResults)
        guard shouldLoadMore else { return }

        search(reset: false)
    }

    func setCityFilter(_ city: String?) {
        let normalized = city?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (normalized?.isEmpty == false) ? normalized : nil
        guard next != cityFilter else { return }
        cityFilter = next
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            search(reset: true)
        }
    }

    func commitCurrentQueryToRecent() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= minQueryLength else { return }
        pushRecent(q)
    }

    private func pushRecent(_ query: String) {
        recentSearches.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
        recentSearches.insert(query, at: 0)
        if recentSearches.count > 10 {
            recentSearches = Array(recentSearches.prefix(10))
        }
    }

    private func isNearEnd(_ item: SearchResultItem, in list: [SearchResultItem], threshold: Int = 5) -> Bool {
        guard list.count > threshold else { return false }
        return list.suffix(threshold).contains(where: { $0.id == item.id })
    }
}
