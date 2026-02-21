import SwiftUI

// MARK: - ItemOptionSheet

/// Sepete eklemeden önce ürün seçeneklerini yapılandıran sayfa
struct ItemOptionSheet: View {
    let item: MenuItem
    let restaurant: Restaurant
    @ObservedObject var cart: CartViewModel
    var onAdded: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var quantity: Int = 1
    @State private var singleSelections: [String: String] = [:]    // groupId -> optionName
    @State private var multiSelections: [String: Set<String>] = [:]  // groupId -> {optionNames}
    @State private var validationError: String?

    // ── Computed ─────────────────────────────────────────────────────────

    private var optionExtrasPerUnit: Double {
        var total: Double = 0
        for group in item.optionGroups {
            switch group.type {
            case .singleSelect:
                if let selectedName = singleSelections[group.id],
                   let opt = group.options.first(where: { $0.name == selectedName }) {
                    total += opt.extraPrice
                }
            case .multiSelect:
                let names = multiSelections[group.id] ?? []
                for name in names {
                    if let opt = group.options.first(where: { $0.name == name }) {
                        total += opt.extraPrice
                    }
                }
            }
        }
        return total
    }

    private var pricePerUnit: Double { item.discountedPrice + optionExtrasPerUnit }
    private var totalPrice: Double { pricePerUnit * Double(quantity) }

    private func isValid() -> Bool {
        for group in item.optionGroups where group.isRequired {
            switch group.type {
            case .singleSelect:
                if singleSelections[group.id] == nil {
                    validationError = "\"\(group.name)\" seçimi zorunludur."
                    return false
                }
            case .multiSelect:
                let count = multiSelections[group.id]?.count ?? 0
                if count < group.minSelections {
                    validationError = "\"\(group.name)\" için en az \(group.minSelections) seçim gereklidir."
                    return false
                }
            }
        }
        validationError = nil
        return true
    }

    // ── Body ──────────────────────────────────────────────────────────────

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // Header image + item info
                    itemHeader

                    Divider().padding(.vertical, 8)

                    // Option Groups
                    ForEach(item.optionGroups) { group in
                        OptionGroupSection(
                            group: group,
                            singleSelection: Binding(
                                get: { singleSelections[group.id] },
                                set: { singleSelections[group.id] = $0 }
                            ),
                            multiSelection: Binding(
                                get: { multiSelections[group.id] ?? [] },
                                set: { multiSelections[group.id] = $0 }
                            )
                        )
                        Divider().padding(.vertical, 4)
                    }

                    if let error = validationError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                            .padding(.top, 4)
                    }

                    Spacer(minLength: 100)
                }
            }
            .navigationTitle("Özelleştir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
        }
        .onAppear { prefillDefaults() }
    }

    // ── Sub-views ─────────────────────────────────────────────────────────

    private var itemHeader: some View {
        HStack(spacing: 14) {
            if let urlString = item.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { Color.orange.opacity(0.12) }
                    .frame(width: 80, height: 80).cornerRadius(12).clipped()
            } else {
                RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12))
                    .frame(width: 80, height: 80)
                    .overlay(Image(systemName: "fork.knife").foregroundColor(.orange))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.headline)
                if !item.description.isEmpty {
                    Text(item.description).font(.caption).foregroundColor(.secondary).lineLimit(2)
                }
                if item.discountPercent > 0 {
                    HStack(spacing: 6) {
                        Text("₺\(String(format: "%.2f", item.price))").strikethrough()
                            .font(.caption).foregroundColor(.secondary)
                        Text("₺\(String(format: "%.2f", item.discountedPrice))")
                            .fontWeight(.bold).foregroundColor(.orange)
                    }
                } else {
                    Text("₺\(String(format: "%.2f", item.price))")
                        .fontWeight(.bold).foregroundColor(.orange)
                }
            }
            Spacer()
        }
        .padding()
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 20) {
                // Quantity stepper
                HStack(spacing: 16) {
                    Button {
                        if quantity > 1 { quantity -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2).foregroundColor(quantity > 1 ? .orange : .gray)
                    }
                    Text("\(quantity)").font(.headline).frame(minWidth: 28)
                    Button { quantity += 1 } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2).foregroundColor(.orange)
                    }
                }

                Spacer()

                Button {
                    guard isValid() else { return }
                    let groups = buildSelectedGroups()
                    cart.addItem(
                        item,
                        quantity: quantity,
                        selectedOptionGroups: groups,
                        optionExtrasPerUnit: optionExtrasPerUnit,
                        restaurantId: restaurant.id,
                        restaurantName: restaurant.name,
                        restaurant: restaurant
                    )
                    onAdded?()
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Text("Sepete Ekle")
                        Text("₺\(String(format: "%.2f", totalPrice))")
                            .fontWeight(.bold)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.orange)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal).padding(.bottom, 8)
        }
        .background(Color(.systemBackground))
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private func prefillDefaults() {
        for group in item.optionGroups {
            switch group.type {
            case .singleSelect:
                if let def = group.options.first(where: { $0.isDefault }) {
                    singleSelections[group.id] = def.name
                } else if group.isRequired, let first = group.options.first {
                    singleSelections[group.id] = first.name
                }
            case .multiSelect:
                let defs = Set(group.options.filter { $0.isDefault }.map { $0.name })
                if !defs.isEmpty { multiSelections[group.id] = defs }
            }
        }
    }

    private func buildSelectedGroups() -> [SelectedOptionGroup] {
        var groups: [SelectedOptionGroup] = []
        for group in item.optionGroups {
            switch group.type {
            case .singleSelect:
                if let name = singleSelections[group.id] {
                    let extra = group.options.first(where: { $0.name == name })?.extraPrice ?? 0
                    groups.append(SelectedOptionGroup(groupName: group.name, selectedOptions: [name], extraTotal: extra))
                }
            case .multiSelect:
                let names = Array(multiSelections[group.id] ?? [])
                if !names.isEmpty {
                    let extra = names.compactMap { n in group.options.first(where: { $0.name == n })?.extraPrice }.reduce(0, +)
                    groups.append(SelectedOptionGroup(groupName: group.name, selectedOptions: names.sorted(), extraTotal: extra))
                }
            }
        }
        return groups
    }
}

// MARK: - OptionGroupSection

private struct OptionGroupSection: View {
    let group: MenuItemOptionGroup
    @Binding var singleSelection: String?
    @Binding var multiSelection: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.name).font(.subheadline).fontWeight(.semibold)
                        if group.isRequired {
                            Text("Zorunlu").font(.caption2).foregroundColor(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.red).cornerRadius(4)
                        } else {
                            Text("İsteğe bağlı").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    if group.type == .multiSelect && group.maxSelections > 1 {
                        Text("En fazla \(group.maxSelections) seçim").font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: group.type == .multiSelect ? "checkmark.square" : "circle")
                    .foregroundColor(.secondary).font(.caption)
            }
            .padding(.horizontal)

            // Options
            ForEach(group.options) { option in
                OptionRow(
                    option: option,
                    groupType: group.type,
                    isSelected: isSelected(option),
                    onTap: { toggleOption(option, group: group) }
                )
            }
        }
        .padding(.vertical, 8)
    }

    private func isSelected(_ option: MenuItemOption) -> Bool {
        switch group.type {
        case .singleSelect:
            return singleSelection == option.name
        case .multiSelect:
            return multiSelection.contains(option.name)
        }
    }

    private func toggleOption(_ option: MenuItemOption, group: MenuItemOptionGroup) {
        switch group.type {
        case .singleSelect:
            singleSelection = option.name
        case .multiSelect:
            if multiSelection.contains(option.name) {
                multiSelection.remove(option.name)
            } else {
                if multiSelection.count < group.maxSelections {
                    multiSelection.insert(option.name)
                }
            }
        }
    }
}

// MARK: - OptionRow

private struct OptionRow: View {
    let option: MenuItemOption
    let groupType: OptionGroupType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Selection indicator
                ZStack {
                    if groupType == .singleSelect {
                        Circle()
                            .stroke(isSelected ? Color.orange : Color(.systemGray4), lineWidth: 2)
                            .frame(width: 22, height: 22)
                        if isSelected {
                            Circle().fill(Color.orange).frame(width: 12, height: 12)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(isSelected ? Color.orange : Color(.systemGray4), lineWidth: 2)
                            .frame(width: 22, height: 22)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.orange)
                        }
                    }
                }

                Text(option.name)
                    .font(.subheadline)
                    .foregroundColor(.primary)

                Spacer()

                if option.extraPrice > 0 {
                    Text("+₺\(String(format: "%.2f", option.extraPrice))")
                        .font(.subheadline).foregroundColor(.secondary)
                } else if option.isDefault {
                    Text("Standart").font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(isSelected ? Color.orange.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
