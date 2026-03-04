import SwiftUI

struct SearchView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var vm = SearchViewModel()
    @State private var resolvingItemIds: Set<String> = []
    @State private var optionSheetPayload: OptionSheetPayload?
    @State private var addErrorMessage: String?
    @State private var restaurantCache: [String: Restaurant] = [:]

    private let restaurantAPI = RestaurantAPIService()

    var body: some View {
        NavigationView {
            List {
                if vm.query.isEmpty {
                    if !vm.recentSearches.isEmpty {
                        Section("Son Aramalar") {
                            ForEach(vm.recentSearches, id: \.self) { item in
                                Button(item) {
                                    vm.query = item
                                    vm.commitCurrentQueryToRecent()
                                }
                                    .foregroundColor(.primary)
                            }
                        }
                    }

                    Section("Önerilen Aramalar") {
                        ForEach(["döner", "zurna döner", "burger menü", "pizza"], id: \.self) { item in
                            Button(item) {
                                vm.query = item
                                vm.commitCurrentQueryToRecent()
                            }
                                .foregroundColor(.primary)
                        }
                    }
                } else {
                    if !vm.storeResults.isEmpty {
                        Section("Mağazalar") {
                            ForEach(vm.storeResults) { item in
                                if let restaurantId = item.restaurantId {
                                    NavigationLink {
                                        SearchRestaurantDestination(
                                            restaurantId: restaurantId,
                                            viewModel: viewModel,
                                            restaurantAPI: restaurantAPI
                                        )
                                    } label: {
                                        SearchRow(item: item, query: vm.query)
                                    }
                                    .buttonStyle(.plain)
                                    .subtleCardTransition()
                                    .onAppear { vm.loadMoreIfNeeded(currentItem: item) }
                                } else {
                                    SearchRow(item: item, query: vm.query)
                                        .subtleCardTransition()
                                        .onAppear { vm.loadMoreIfNeeded(currentItem: item) }
                                }
                            }
                        }
                    }

                    if !vm.menuResults.isEmpty {
                        Section("Menü") {
                            ForEach(vm.menuResults) { item in
                                SearchRow(
                                    item: item,
                                    query: vm.query,
                                    showsAddButton: true,
                                    isAdding: resolvingItemIds.contains(item.id),
                                    onAddTap: { quickAddToCart(item) }
                                )
                                    .subtleCardTransition()
                                    .onAppear { vm.loadMoreIfNeeded(currentItem: item) }
                            }
                        }
                    }

                    if !vm.similarMenuResults.isEmpty {
                        Section("Benzer Ürünler") {
                            ForEach(vm.similarMenuResults) { item in
                                SearchRow(
                                    item: item,
                                    query: vm.query,
                                    showsAddButton: true,
                                    isAdding: resolvingItemIds.contains(item.id),
                                    onAddTap: { quickAddToCart(item) }
                                )
                                .subtleCardTransition()
                            }
                        }
                    }

                    if vm.isLoading || vm.isAwaitingSearch {
                        Section {
                            ProgressView("Aranıyor...")
                        }
                    }

                    if let error = vm.error {
                        Section {
                            Text(error)
                                .foregroundColor(.red)
                        }
                    }

                          if !vm.isLoading,
                              !vm.isAwaitingSearch,
                              vm.hasCompletedSearch,
                       vm.storeResults.isEmpty,
                       vm.menuResults.isEmpty,
                       vm.similarMenuResults.isEmpty {
                        Section {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("Sonuç bulunamadı")
                                    .font(.headline)
                                Text("Farklı bir arama terimi deneyin.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Ara")
            .animation(AppMotion.standard, value: vm.isLoading)
            .animation(AppMotion.standard, value: vm.isAwaitingSearch)
            .animation(AppMotion.spring, value: vm.storeResults.count)
            .animation(AppMotion.spring, value: vm.menuResults.count)
            .animation(AppMotion.spring, value: vm.similarMenuResults.count)
            .searchable(text: $vm.query, prompt: "Mağaza veya menü ara")
            .onSubmit(of: .search) {
                vm.commitCurrentQueryToRecent()
            }
            .onAppear {
                vm.setCityFilter(viewModel.authService.currentUser?.city)
                let incoming = viewModel.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                if incoming.count >= 2, incoming != vm.query {
                    vm.query = incoming
                    vm.commitCurrentQueryToRecent()
                }
            }
            .onReceive(viewModel.authService.$user) { user in
                vm.setCityFilter(user?.city)
            }
            .onChange(of: viewModel.globalSearchQuery) { newValue in
                let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard normalized != vm.query else { return }
                vm.query = normalized
            }
            .onChange(of: vm.query) { newValue in
                if viewModel.globalSearchQuery != newValue {
                    viewModel.globalSearchQuery = newValue
                }
            }
            .sheet(item: $optionSheetPayload) { payload in
                ItemOptionSheet(
                    item: payload.item,
                    restaurant: payload.restaurant,
                    cart: viewModel.cart,
                    onAdded: nil
                )
            }
            .alert("Hata", isPresented: .constant(addErrorMessage != nil)) {
                Button("Tamam") { addErrorMessage = nil }
            } message: {
                Text(addErrorMessage ?? "")
            }
        }
    }

    private func quickAddToCart(_ result: SearchResultItem) {
        guard result.entityType == .menu else { return }
        guard let restaurantId = result.restaurantId else {
            addErrorMessage = "Ürün restoran bilgisi eksik olduğu için sepete eklenemedi."
            return
        }
        guard !resolvingItemIds.contains(result.id) else { return }

        resolvingItemIds.insert(result.id)

        Task {
            defer { Task { @MainActor in resolvingItemIds.remove(result.id) } }
            do {
                let restaurant: Restaurant
                if let cached = restaurantCache[restaurantId] {
                    restaurant = cached
                } else {
                    let fetched = try await restaurantAPI.fetchDetail(id: restaurantId)
                    restaurantCache[restaurantId] = fetched
                    restaurant = fetched
                }

                guard let menuItem = restaurant.menu.first(where: { $0.id == result.id }) else {
                    await MainActor.run {
                        addErrorMessage = "Ürün detayına ulaşılamadı."
                    }
                    return
                }

                await MainActor.run {
                    if menuItem.optionGroups.isEmpty {
                        viewModel.cart.addItem(
                            menuItem,
                            quantity: 1,
                            restaurantId: restaurant.id,
                            restaurantName: restaurant.name,
                            restaurant: restaurant
                        )
                    } else {
                        optionSheetPayload = OptionSheetPayload(item: menuItem, restaurant: restaurant)
                    }
                }
            } catch {
                await MainActor.run {
                    addErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct SearchRow: View {
    let item: SearchResultItem
    let query: String
    var showsAddButton: Bool = false
    var isAdding: Bool = false
    var onAddTap: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HighlightedText(text: item.title, query: query)
                    .font(.headline)
                    .foregroundColor(.primary)

                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let restaurantName = item.restaurantName,
                   item.entityType == .menu {
                    Text(restaurantName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if item.entityType == .menu, let price = item.price {
                    Text("₺\(String(format: "%.2f", price))")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                }
            }

            if item.entityType == .store, let rating = item.rating, rating > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", rating))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 8)

            if showsAddButton, item.entityType == .menu {
                Button(action: { onAddTap?() }) {
                    if isAdding {
                        ProgressView()
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                    }
                }
                .buttonStyle(.plain)
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel("Sepete ekle")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts: [String] = [item.title]
        if let subtitle = item.subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        if let name = item.restaurantName, !name.isEmpty { parts.append(name) }
        return parts.joined(separator: ", ")
    }
}

private struct OptionSheetPayload: Identifiable {
    let id = UUID()
    let item: MenuItem
    let restaurant: Restaurant
}

private struct SearchRestaurantDestination: View {
    let restaurantId: String
    @ObservedObject var viewModel: AppViewModel
    let restaurantAPI: RestaurantAPIService

    @State private var restaurant: Restaurant?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let restaurant {
                RestaurantDetailView(restaurant: restaurant, viewModel: viewModel)
            } else if isLoading {
                VStack(spacing: 12) {
                    ProgressView("Mağaza yükleniyor...")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "storefront")
                        .font(.system(size: 42))
                        .foregroundColor(.secondary)
                    Text(errorMessage ?? "Mağaza detayına ulaşılamadı.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .task {
            guard restaurant == nil else { return }
            do {
                restaurant = try await restaurantAPI.fetchDetail(id: restaurantId)
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

private struct HighlightedText: View {
    let text: String
    let query: String

    var body: some View {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            Text(text)
        } else {
            highlighted(text: text, query: trimmedQuery)
        }
    }

    private func highlighted(text: String, query: String) -> Text {
        guard let range = text.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "tr_TR")
        ) else {
            return Text(text)
        }

        let prefix = String(text[..<range.lowerBound])
        let middle = String(text[range])
        let suffix = String(text[range.upperBound...])

        return Text(prefix) +
        Text(middle).bold().foregroundColor(.orange) +
        Text(suffix)
    }
}
