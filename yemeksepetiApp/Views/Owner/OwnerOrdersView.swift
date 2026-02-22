import SwiftUI

// MARK: - OwnerOrdersView

struct OwnerOrdersView: View {
    let restaurant: Restaurant
    let orders: [Order]              // injected from StoreDashboardView (live)
    @ObservedObject var viewModel: AppViewModel

    @State private var selectedFilter: OrderFilter = .pending
    @State private var errorMessage: String?

    enum OrderFilter: String, CaseIterable {
        case pending       = "Yeni"
        case cancelRequest = "İptal"
        case active        = "Aktif"
        case completed     = "Tamamlandı"
        case all           = "Tümü"
    }

    private var filteredOrders: [Order] {
        switch selectedFilter {
        case .pending:       return orders.filter { $0.status == .pending }
        case .cancelRequest: return orders.filter { $0.cancelRequested }
        case .active:        return orders.filter { [.accepted, .preparing, .onTheWay].contains($0.status) }
        case .completed:     return orders.filter { [.completed, .rejected, .cancelled].contains($0.status) }
        case .all:           return orders
        }
    }

    private var pendingCount: Int       { orders.filter { $0.status == .pending }.count }
    private var cancelRequestCount: Int { orders.filter { $0.cancelRequested }.count }

    var body: some View {
        VStack(spacing: 0) {
            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(OrderFilter.allCases, id: \.self) { filter in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedFilter = filter }
                        } label: {
                            HStack(spacing: 4) {
                                Text(filter.rawValue)
                                let badge = filter == .pending ? pendingCount
                                           : filter == .cancelRequest ? cancelRequestCount : 0
                                if badge > 0 {
                                    Text("\(badge)")
                                        .font(.caption2).fontWeight(.bold)
                                        .foregroundColor(.white).padding(4)
                                        .background(filter == .cancelRequest ? Color.orange : Color.red)
                                        .clipShape(Circle())
                                }
                            }
                            .font(.subheadline.weight(selectedFilter == filter ? .semibold : .regular))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(selectedFilter == filter ? Color.orange : Color(.systemGray6))
                            .foregroundColor(selectedFilter == filter ? .white : .primary)
                            .cornerRadius(20)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 10)

            Divider()

            if filteredOrders.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "tray").font(.system(size: 48)).foregroundColor(.gray.opacity(0.5))
                    Text("Bu kategoride sipariş yok").foregroundColor(.secondary)
                }
                Spacer()
            } else {
                // ScrollView+ForEach so SwiftUI re-renders each card when order data changes
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredOrders) { order in
                            OwnerOrderCard(order: order) { newStatus in
                                updateStatus(order: order, status: newStatus)
                            } onHandleCancelRequest: { approve in
                                handleCancelRequest(order: order, approve: approve)
                            }
                            // Force full card redraw when status or cancel request changes
                            .id("\(order.id)-\(order.status.rawValue)-\(order.cancelRequested)")
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .alert("Hata", isPresented: .constant(errorMessage != nil)) {
            Button("Tamam") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func updateStatus(order: Order, status: OrderStatus) {
        viewModel.orderService.updateOrderStatus(orderId: order.id, status: status) { error in
            if let error { errorMessage = error.localizedDescription }
            if status == .completed {
                viewModel.orderService.incrementSuccessfulOrders(restaurantId: restaurant.id)
            }
        }
    }

    private func handleCancelRequest(order: Order, approve: Bool) {
        viewModel.orderService.handleCancelRequest(orderId: order.id, approve: approve) { error in
            if let error { errorMessage = error.localizedDescription }
        }
    }
}

// MARK: - OwnerOrderCard

private struct OwnerOrderCard: View {
    let order: Order
    let onStatusChange: (OrderStatus) -> Void
    let onHandleCancelRequest: (Bool) -> Void

    @State private var isExpanded = false

    private var statusColor: Color {
        switch order.status {
        case .pending:   return .orange
        case .accepted:  return .blue
        case .rejected:  return .red
        case .preparing: return .yellow
        case .onTheWay:  return .teal
        case .completed: return .green
        case .cancelled: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.userEmail).font(.caption).foregroundColor(.secondary)
                    Text(order.formattedDate).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: order.status.icon).font(.caption)
                    Text(order.status.displayName).font(.caption).fontWeight(.semibold)
                }
                .foregroundColor(statusColor)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(statusColor.opacity(0.12))
                .cornerRadius(8)
            }

            Text(order.items.map { "\($0.quantity)x \($0.name)" }.joined(separator: " · "))
                .font(.subheadline).lineLimit(isExpanded ? nil : 2)

            HStack {
                Label(order.paymentMethod.displayName, systemImage: "creditcard")
                    .font(.caption).foregroundColor(.secondary)
                if let addr = order.deliveryAddress {
                    Text("· \(addr.district)").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text("₺\(String(format: "%.2f", order.total))").fontWeight(.bold).foregroundColor(.orange)
            }

            if let note = order.note, !note.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "note.text").font(.caption).foregroundColor(.secondary)
                    Text(note).font(.caption).foregroundColor(.secondary).lineLimit(2)
                }
            }

            // Cancel request banner
            if order.cancelRequested {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text("İptal Talebi").font(.caption).fontWeight(.bold).foregroundColor(.orange)
                    }
                    if !order.cancelReason.isEmpty {
                        Text("Müşteri sebebi: \(order.cancelReason)")
                            .font(.caption).foregroundColor(.primary).lineLimit(4)
                    }
                    HStack(spacing: 8) {
                        Button { onHandleCancelRequest(false) } label: {
                            Text("Reddet").font(.caption).fontWeight(.semibold).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(Color.gray).cornerRadius(8)
                        }
                        Button { onHandleCancelRequest(true) } label: {
                            Text("İptali Onayla").font(.caption).fontWeight(.semibold).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(Color.red).cornerRadius(8)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(10)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(order.items) { item in
                        HStack {
                            Text("\(item.quantity)x \(item.name)").font(.caption)
                            Spacer()
                            Text("₺\(String(format: "%.2f", item.lineTotal))").font(.caption).foregroundColor(.secondary)
                        }
                        if !item.optionSummary.isEmpty {
                            Text("  \(item.optionSummary)").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8).background(Color(.systemGray6)).cornerRadius(8)

                if let addr = order.deliveryAddress {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Teslimat Adresi", systemImage: "mappin.circle.fill")
                            .font(.caption.weight(.semibold)).foregroundColor(.secondary)
                        Text(addr.fullAddress).font(.caption2).foregroundColor(.primary)
                        if !addr.phone.isEmpty {
                            Label(addr.phone, systemImage: "phone")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .padding(8).background(Color(.systemGray6)).cornerRadius(8)
                }
            }

            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(isExpanded ? "Gizle" : "Detaylar").font(.caption)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.caption)
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            actionButtons
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .padding(.horizontal, 4).padding(.vertical, 2)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch order.status {
        case .pending:
            HStack(spacing: 10) {
                Button { onStatusChange(.rejected) } label: {
                    Label("Reddet", systemImage: "xmark.circle")
                        .font(.subheadline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(10)
                        .background(Color.red).cornerRadius(10)
                }
                Button { onStatusChange(.accepted) } label: {
                    Label("Kabul Et", systemImage: "checkmark.circle")
                        .font(.subheadline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(10)
                        .background(Color.green).cornerRadius(10)
                }
            }
            .buttonStyle(.plain)

        case .accepted:
            Button { onStatusChange(.preparing) } label: {
                Label("Hazırlanıyor", systemImage: "flame")
                    .font(.subheadline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(10)
                    .background(Color.orange).cornerRadius(10)
            }
            .buttonStyle(.plain)

        case .preparing:
            Button { onStatusChange(.onTheWay) } label: {
                Label("Yola Çıktı", systemImage: "bicycle")
                    .font(.subheadline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(10)
                    .background(Color.teal).cornerRadius(10)
            }
            .buttonStyle(.plain)

        case .onTheWay:
            Button { onStatusChange(.completed) } label: {
                Label("Teslim Edildi", systemImage: "checkmark.seal.fill")
                    .font(.subheadline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(10)
                    .background(Color.green).cornerRadius(10)
            }
            .buttonStyle(.plain)

        default:
            EmptyView()
        }
    }
}
