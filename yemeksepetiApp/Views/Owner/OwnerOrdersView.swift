import SwiftUI
import UIKit

// MARK: - OwnerOrdersView

struct OwnerOrdersView: View {
    let restaurant: Restaurant
    @Binding var orders: [Order]              // injected from StoreDashboardView (live)
    @ObservedObject var viewModel: AppViewModel

    @State private var selectedFilter: OrderFilter = .pending
    @State private var errorMessage: String?
    @State private var statusUpdatingOrderIds: Set<String> = []
    @State private var cancelDecisionOrderIds: Set<String> = []
    @State private var pendingOwnerAction: PendingOwnerAction?
    @State private var lastObservedPendingCount: Int = 0
    @State private var toastMessage: String?
    @State private var toastDismissWorkItem: DispatchWorkItem?

    private enum PendingOwnerAction: Identifiable {
        case status(order: Order, next: OrderStatus)
        case cancelDecision(order: Order, approve: Bool)

        var id: String {
            switch self {
            case .status(let order, let next):
                return "status-\(order.id)-\(next.rawValue)"
            case .cancelDecision(let order, let approve):
                return "cancel-decision-\(order.id)-\(approve)"
            }
        }

        var title: String {
            switch self {
            case .status:
                return "Durum Değişikliği"
            case .cancelDecision:
                return "İptal Talebi Kararı"
            }
        }

        var message: String {
            switch self {
            case .status(_, let next):
                return "Sipariş durumu '\(next.displayName)' olarak güncellenecek. Emin misiniz?"
            case .cancelDecision(_, let approve):
                return approve
                    ? "Sipariş iptal edilecek. Emin misiniz?"
                    : "İptal talebi reddedilecek. Emin misiniz?"
            }
        }

        var confirmButtonTitle: String {
            switch self {
            case .status:
                return "Evet, Güncelle"
            case .cancelDecision(_, let approve):
                return approve ? "Evet, İptal Et" : "Evet, Reddet"
            }
        }

        var confirmRole: ButtonRole? {
            switch self {
            case .cancelDecision(_, let approve):
                return approve ? .destructive : nil
            default:
                return nil
            }
        }
    }

    enum OrderFilter: String, CaseIterable {
        case pending       = "Yeni"
        case cancelRequest = "İptal"
        case active        = "Aktif"
        case completed     = "Tamamlandı"
        case all           = "Tümü"

        var systemImage: String {
            switch self {
            case .pending: return "clock.badge.exclamationmark"
            case .cancelRequest: return "exclamationmark.triangle"
            case .active: return "bolt"
            case .completed: return "checkmark.seal"
            case .all: return "line.3.horizontal.decrease.circle"
            }
        }
    }

    private var sortedOrders: [Order] {
        orders.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var filteredOrders: [Order] {
        func statusPriority(_ status: OrderStatus) -> Int {
            switch status {
            case .accepted: return 0
            case .preparing: return 1
            case .onTheWay: return 2
            case .pending: return 3
            case .rejected: return 4
            case .cancelled: return 5
            case .completed: return 6
            }
        }

        func byPriority(_ list: [Order]) -> [Order] {
            list.sorted { lhs, rhs in
                let lp = statusPriority(lhs.status)
                let rp = statusPriority(rhs.status)
                if lp == rp {
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.updatedAt > rhs.updatedAt
                    }
                    return lhs.createdAt > rhs.createdAt
                }
                return lp < rp
            }
        }

        func byReverseChronological(_ list: [Order]) -> [Order] {
            list.sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.updatedAt > rhs.updatedAt
            }
        }

        switch selectedFilter {
        case .pending:       return byPriority(sortedOrders.filter { $0.status == .pending })
        case .cancelRequest: return byPriority(sortedOrders.filter { $0.cancelRequested })
        case .active:        return byPriority(sortedOrders.filter { [.accepted, .preparing, .onTheWay].contains($0.status) })
        case .completed:     return byReverseChronological(sortedOrders.filter { [.completed, .rejected, .cancelled].contains($0.status) })
        case .all:           return byPriority(sortedOrders)
        }
    }

    private var pendingCount: Int       { orders.filter { $0.status == .pending }.count }
    private var cancelRequestCount: Int { orders.filter { $0.cancelRequested }.count }
    private var activeCount: Int        { orders.filter { [.accepted, .preparing, .onTheWay].contains($0.status) }.count }

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
                                Image(systemName: filter.systemImage)
                                    .font(.caption)
                                Text(filter.rawValue)
                                let badge = filter == .pending ? pendingCount
                                           : filter == .cancelRequest ? cancelRequestCount
                                           : filter == .active ? activeCount : 0
                                if badge > 0 {
                                    Text("\(badge)")
                                        .font(.caption2).fontWeight(.bold)
                                        .foregroundColor(.white).padding(4)
                                        .background(filter == .cancelRequest ? Color.orange : (filter == .active ? Color.blue : Color.red))
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
                                confirmStatusChange(order: order, status: newStatus)
                            } onHandleCancelRequest: { approve in
                                confirmCancelDecision(order: order, approve: approve)
                            }
                            .opacity(isProcessing(orderId: order.id) ? 0.65 : 1)
                            .overlay(alignment: .topTrailing) {
                                if isProcessing(orderId: order.id) {
                                    ProgressView()
                                        .padding(8)
                                }
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
        .onAppear {
            lastObservedPendingCount = pendingCount
        }
        .onChange(of: pendingCount) { newValue in
            if selectedFilter == .active && newValue > lastObservedPendingCount {
                notifyIncomingOrder()
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedFilter = .pending
                }
            }
            lastObservedPendingCount = newValue
        }
        .overlay(alignment: .top) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.orange.opacity(0.96))
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .alert(item: $pendingOwnerAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: .default(Text(action.confirmButtonTitle), action: {
                    executePendingAction(action)
                }),
                secondaryButton: .cancel(Text("Vazgeç"))
            )
        }
    }

    private func confirmStatusChange(order: Order, status: OrderStatus) {
        pendingOwnerAction = .status(order: order, next: status)
    }

    private func confirmCancelDecision(order: Order, approve: Bool) {
        pendingOwnerAction = .cancelDecision(order: order, approve: approve)
    }

    private func executePendingAction(_ action: PendingOwnerAction) {
        switch action {
        case .status(let order, let next):
            updateStatus(order: order, status: next)
        case .cancelDecision(let order, let approve):
            handleCancelRequest(order: order, approve: approve)
        }
    }

    private func notifyIncomingOrder() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            toastMessage = "Yeni sipariş geldi"
        }

        toastDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                toastMessage = nil
            }
        }
        toastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }

    private func isProcessing(orderId: String) -> Bool {
        statusUpdatingOrderIds.contains(orderId) || cancelDecisionOrderIds.contains(orderId)
    }

    private func patchOrder(orderId: String, mutate: (inout Order) -> Void) {
        guard let index = orders.firstIndex(where: { $0.id == orderId }) else { return }
        mutate(&orders[index])
    }

    private func mergeServerOrder(_ updated: Order) {
        guard let index = orders.firstIndex(where: { $0.id == updated.id }) else { return }
        orders[index] = updated
    }

    private func updateStatus(order: Order, status: OrderStatus) {
        guard !isProcessing(orderId: order.id) else { return }
        statusUpdatingOrderIds.insert(order.id)
        let previous = order

        let isLastPendingResolution = order.status == .pending
            && [.accepted, .preparing, .onTheWay, .rejected].contains(status)
            && pendingCount <= 1
        let shouldAutoFocusActive = isLastPendingResolution

        if shouldAutoFocusActive {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFilter = .active
            }
        }

        patchOrder(orderId: order.id) { item in
            item.status = status
            item.updatedAt = Date()
            if status == .cancelled || status == .completed || status == .rejected {
                item.cancelRequested = false
            }
        }

        viewModel.orderService.updateOrderStatus(orderId: order.id, status: status) { result in
            statusUpdatingOrderIds.remove(order.id)
            switch result {
            case .success(let updated):
                mergeServerOrder(updated)
                if status == .completed {
                    viewModel.orderService.incrementSuccessfulOrders(restaurantId: restaurant.id)
                }
            case .failure(let error):
                patchOrder(orderId: order.id) { item in
                    item = previous
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleCancelRequest(order: Order, approve: Bool) {
        guard !isProcessing(orderId: order.id) else { return }
        cancelDecisionOrderIds.insert(order.id)
        let previous = order

        patchOrder(orderId: order.id) { item in
            item.cancelRequested = false
            if approve {
                item.status = .cancelled
            }
            item.updatedAt = Date()
        }

        viewModel.orderService.handleCancelRequest(orderId: order.id, approve: approve) { result in
            cancelDecisionOrderIds.remove(order.id)
            switch result {
            case .success(let updated):
                mergeServerOrder(updated)
            case .failure(let error):
                patchOrder(orderId: order.id) { item in
                    item = previous
                }
                errorMessage = error.localizedDescription
            }
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
