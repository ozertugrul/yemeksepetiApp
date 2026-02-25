import SwiftUI

// MARK: - UserOrdersView

struct UserOrdersView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var orders: [Order] = []
    @State private var isLoading = true
    @State private var selectedFilter: OrderFilter = .active
    @State private var reviewingOrder: Order?
    @State private var cancellingOrderId: String?
    @State private var errorMessage: String?
    @State private var listenerReg: ListenerRegistration?
    // Cancel request sheet
    @State private var cancelRequestOrder: Order?
    @State private var cancelReasonText: String = ""

    enum OrderFilter: String, CaseIterable {
        case active = "Aktif"
        case past   = "Geçmiş"
    }

    private var activeOrders: [Order] {
        orders.filter { [.pending, .accepted, .preparing, .onTheWay].contains($0.status) }
    }
    private var pastOrders: [Order] {
        orders.filter { [.completed, .rejected, .cancelled].contains($0.status) }
    }
    private var displayed: [Order] { selectedFilter == .active ? activeOrders : pastOrders }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedFilter) {
                ForEach(OrderFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.vertical, 10)

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Yükleniyor...")
                Spacer()
            } else if displayed.isEmpty {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: selectedFilter == .active ? "clock" : "bag")
                        .font(.system(size: 52)).foregroundColor(.orange.opacity(0.4))
                    Text(selectedFilter == .active ? "Aktif sipariş yok" : "Geçmiş sipariş yok")
                        .font(.title3).fontWeight(.semibold)
                    Text(selectedFilter == .active
                         ? "Verdiğiniz siparişler burada görünecek."
                         : "Tamamlanan siparişleriniz burada görünecek.")
                        .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(displayed) { order in
                            UserOrderCard(
                                order: order,
                                isCancelling: cancellingOrderId == order.id,
                                onRateTap: { reviewingOrder = order },
                                onCancelTap: { cancelRequestOrder = order; cancelReasonText = "" }
                            )
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Siparişlerim")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { startListening() }
        .onDisappear { listenerReg?.remove() }
        .sheet(item: $reviewingOrder) { order in
            OrderReviewSheet(order: order, viewModel: viewModel) { reviewingOrder = nil }
        }
        .sheet(item: $cancelRequestOrder) { order in
            CancelRequestSheet(
                order: order,
                reason: $cancelReasonText,
                isSending: cancellingOrderId == order.id
            ) {
                submitCancelRequest(order)
            }
        }
        .alert("Hata", isPresented: .constant(errorMessage != nil)) {
            Button("Tamam") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func startListening() {
        guard let uid = viewModel.authService.currentUser?.id else { isLoading = false; return }
        // Önbellekte veri varsa spinner gösterme — arka planda yenile
        if orders.isEmpty { isLoading = true }
        listenerReg?.remove()
        listenerReg = viewModel.orderService.listenUserOrders(userId: uid) { fetched in
            orders = fetched
            isLoading = false
        }
    }

    private func cancelOrder(_ order: Order) {
        cancellingOrderId = order.id
        viewModel.orderService.cancelOrder(orderId: order.id) { error in
            cancellingOrderId = nil
            if let error { errorMessage = error.localizedDescription }
        }
    }

    private func submitCancelRequest(_ order: Order) {
        let reason = cancelReasonText.trimmingCharacters(in: .whitespaces)
        guard !reason.isEmpty else { return }
        cancellingOrderId = order.id
        viewModel.orderService.requestCancellation(orderId: order.id, reason: reason) { error in
            cancellingOrderId = nil
            cancelRequestOrder = nil
            if let error { errorMessage = error.localizedDescription }
        }
    }
}

// MARK: - UserOrderCard

struct UserOrderCard: View {
    let order: Order
    var isCancelling: Bool = false
    let onRateTap: () -> Void
    let onCancelTap: () -> Void

    private var statusColor: Color {
        switch order.status {
        case .pending:            return .orange
        case .accepted:           return .blue
        case .preparing:          return .yellow
        case .onTheWay:           return .teal
        case .completed:          return .green
        case .rejected, .cancelled: return .gray
        }
    }

    private var canCancel: Bool {
        !order.cancelRequested &&
        [OrderStatus.pending, .accepted, .preparing].contains(order.status)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(order.restaurantName).font(.headline).lineLimit(1)
                Spacer()
                Text(order.formattedDate).font(.caption).foregroundColor(.secondary)
            }

            HStack(spacing: 5) {
                Image(systemName: order.status.icon).font(.caption)
                Text(order.status.displayName).font(.caption).fontWeight(.semibold)
            }
            .foregroundColor(statusColor)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(statusColor.opacity(0.1)).cornerRadius(8)

            // Cancel-pending badge
            if order.cancelRequested {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark").foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("İptal Talebi Gönderildi").font(.caption).fontWeight(.semibold).foregroundColor(.orange)
                        if !order.cancelReason.isEmpty {
                            Text("Sebep: \(order.cancelReason)").font(.caption2).foregroundColor(.secondary).lineLimit(2)
                        }
                    }
                    Spacer()
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
            }

            Text(order.items.map { item -> String in
                var line = "\(item.quantity)x \(item.name)"
                if !item.optionSummary.isEmpty {
                    line += " (\(item.optionSummary))"
                }
                return line
            }.joined(separator: "\n"))
                .font(.subheadline).foregroundColor(.secondary)

            HStack {
                Label(order.paymentMethod.displayName, systemImage: "creditcard")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("₺\(String(format: "%.2f", order.total))")
                    .font(.subheadline).fontWeight(.bold).foregroundColor(.orange)
            }

            if let code = order.pickupCode {
                HStack(spacing: 6) {
                    Image(systemName: "qrcode").foregroundColor(.orange)
                    Text("Teslim Kodu: \(code)").font(.subheadline).fontWeight(.bold)
                }
                .padding(8).background(Color.orange.opacity(0.08)).cornerRadius(8)
            }

            if let note = order.note, !note.isEmpty {
                Text("Not: \(note)").font(.caption).foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                if canCancel {
                    Button(action: onCancelTap) {
                        Group {
                            if isCancelling {
                                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(Color(.systemGray5)).cornerRadius(10)
                            } else {
                                Label("İptal Talep Et", systemImage: "xmark.circle")
                                    .font(.subheadline.weight(.semibold)).foregroundColor(.red)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(Color.red.opacity(0.1)).cornerRadius(10)
                            }
                        }
                    }
                    .buttonStyle(.plain).disabled(isCancelling)
                }

                if order.status == .completed && !order.isReviewed {
                    Button(action: onRateTap) {
                        Label("Değerlendir", systemImage: "star.leadinghalf.filled")
                            .font(.subheadline.weight(.semibold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Color.orange).cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

// MARK: - CancelRequestSheet

struct CancelRequestSheet: View {
    let order: Order
    @Binding var reason: String
    let isSending: Bool
    let onSend: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {

                // Order summary
                VStack(alignment: .leading, spacing: 6) {
                    Text(order.restaurantName).font(.headline)
                    Text(order.items.map { "\($0.quantity)x \($0.name)" }.joined(separator: " · "))
                        .font(.subheadline).foregroundColor(.secondary).lineLimit(2)
                    Text("₺\(String(format: "%.2f", order.total))")
                        .font(.subheadline).fontWeight(.bold).foregroundColor(.orange)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 8) {
                    Label("İptal Sebebi", systemImage: "text.bubble")
                        .font(.headline)
                    Text("Mağaza sahibi talebinizi inceledikten sonra iptal işlemini onaylayacaktır.")
                        .font(.caption).foregroundColor(.secondary)

                    TextEditor(text: $reason)
                        .focused($focused)
                        .frame(minHeight: 100)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(focused ? Color.orange : Color.clear, lineWidth: 1.5)
                        )

                    if reason.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Lütfen bir sebep giriniz.").font(.caption).foregroundColor(.red)
                    }
                }

                Spacer()

                Button {
                    focused = false
                    onSend()
                } label: {
                    HStack {
                        if isSending { ProgressView().tint(.white) }
                        Text(isSending ? "Gönderiliyor..." : "İptal Talebini Gönder")
                            .font(.headline).foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(reason.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.red)
                    .cornerRadius(14)
                }
                .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
            }
            .padding()
            .navigationTitle("İptal Talebi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
        }
        .onAppear { focused = true }
    }
}
