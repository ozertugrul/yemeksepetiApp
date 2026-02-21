import SwiftUI

// MARK: - SalesReportView

struct SalesReportView: View {
    let restaurant: Restaurant
    @ObservedObject var viewModel: AppViewModel

    enum ReportPeriod: String, CaseIterable {
        case daily   = "Günlük"
        case weekly  = "Haftalık"
        case monthly = "Aylık"
        case yearly  = "Yıllık"
    }

    @State private var selectedPeriod: ReportPeriod = .daily
    @State private var orders: [Order] = []
    @State private var isLoading = false

    private var periodRange: (Date, Date) {
        let now = Date()
        let cal = Calendar.current
        switch selectedPeriod {
        case .daily:
            let start = cal.startOfDay(for: now)
            return (start, now)
        case .weekly:
            let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? now
            return (start, now)
        case .monthly:
            let start = cal.date(byAdding: .month, value: -1, to: now) ?? now
            return (start, now)
        case .yearly:
            let start = cal.date(byAdding: .year, value: -1, to: now) ?? now
            return (start, now)
        }
    }

    private var totalRevenue: Double { orders.reduce(0) { $0 + $1.total } }
    private var orderCount: Int { orders.count }
    private var avgOrderValue: Double { orderCount > 0 ? totalRevenue / Double(orderCount) : 0 }

    private var topItems: [(String, Int)] {
        var counts: [String: Int] = [:]
        orders.forEach { order in
            order.items.forEach { item in
                counts[item.name, default: 0] += item.quantity
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    private var dailyBreakdown: [(String, Double)] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")

        switch selectedPeriod {
        case .daily:
            formatter.dateFormat = "HH:00"
            var hourly: [String: Double] = [:]
            orders.forEach { o in
                let hour = formatter.string(from: o.createdAt)
                hourly[hour, default: 0] += o.total
            }
            return hourly.sorted { $0.key < $1.key }
        case .weekly:
            formatter.dateFormat = "EEE"
            var daily: [String: Double] = [:]
            orders.forEach { o in
                let day = formatter.string(from: o.createdAt)
                daily[day, default: 0] += o.total
            }
            return daily.sorted { $0.key < $1.key }
        case .monthly:
            formatter.dateFormat = "dd MMM"
            var daily: [String: Double] = [:]
            orders.forEach { o in
                let d = formatter.string(from: o.createdAt)
                daily[d, default: 0] += o.total
            }
            return daily.sorted { $0.key < $1.key }
        case .yearly:
            formatter.dateFormat = "MMM yy"
            var monthly: [String: Double] = [:]
            orders.forEach { o in
                let m = formatter.string(from: o.createdAt)
                monthly[m, default: 0] += o.total
            }
            return monthly.sorted { $0.key < $1.key }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Period Picker
                Picker("Periyot", selection: $selectedPeriod) {
                    ForEach(ReportPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: selectedPeriod) { _ in loadData() }

                if isLoading {
                    ProgressView("Veriler yükleniyor...").padding()
                } else {
                    // Key metrics
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricCard(title: "Toplam Satış", value: "₺\(String(format: "%.0f", totalRevenue))", icon: "turkishlirasign.circle.fill", color: .orange)
                        MetricCard(title: "Sipariş Sayısı", value: "\(orderCount)", icon: "bag.fill", color: .blue)
                        MetricCard(title: "Ort. Sepet", value: "₺\(String(format: "%.0f", avgOrderValue))", icon: "cart.fill", color: .green)
                    }
                    .padding(.horizontal)

                    // Revenue chart (bar chart simulation)
                    if !dailyBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Satış Grafiği").font(.headline).padding(.horizontal)
                            BarChartView(data: dailyBreakdown)
                                .frame(height: 160)
                                .padding(.horizontal)
                        }
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground))
                        .cornerRadius(14)
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                        .padding(.horizontal)
                    }

                    // Payment method breakdown
                    if !orders.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Ödeme Yöntemi Dağılımı").font(.headline).padding(.horizontal)
                            ForEach(paymentBreakdown(), id: \.0) { method, amount in
                                HStack {
                                    Text(method).font(.subheadline)
                                    Spacer()
                                    Text("₺\(String(format: "%.2f", amount))").font(.subheadline).fontWeight(.semibold)
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground))
                        .cornerRadius(14)
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                        .padding(.horizontal)
                    }

                    // Top items
                    if !topItems.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("En Çok Satan Ürünler").font(.headline).padding(.horizontal)
                            ForEach(topItems.indices, id: \.self) { idx in
                                let item = topItems[idx]
                                HStack {
                                    Text("\(idx + 1).").font(.caption).foregroundColor(.secondary).frame(width: 20)
                                    Text(item.0).font(.subheadline)
                                    Spacer()
                                    Text("\(item.1) adet").font(.subheadline).fontWeight(.semibold).foregroundColor(.orange)
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground))
                        .cornerRadius(14)
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                        .padding(.horizontal)
                    }

                    // All orders (accounting)
                    if !orders.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Muhasebe - Sipariş Listesi").font(.headline).padding(.horizontal)
                            ForEach(orders) { order in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("#\(order.id.prefix(6).uppercased())").font(.caption2).foregroundColor(.secondary)
                                        Text(order.formattedDate).font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text("\(order.itemCount) ürün").font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Text("₺\(String(format: "%.2f", order.total))").font(.subheadline).fontWeight(.semibold)
                                }
                                .padding(.horizontal)
                                Divider().padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground))
                        .cornerRadius(14)
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .onAppear { loadData() }
    }

    private func loadData() {
        isLoading = true
        let (start, end) = periodRange
        viewModel.orderService.fetchSalesData(restaurantId: restaurant.id, from: start, to: end) { fetched in
            orders = fetched
            isLoading = false
        }
    }

    private func paymentBreakdown() -> [(String, Double)] {
        var breakdown: [String: Double] = [:]
        orders.forEach { o in
            breakdown[o.paymentMethod.displayName, default: 0] += o.total
        }
        return breakdown.sorted { $0.value > $1.value }
    }
}

// MARK: - MetricCard

private struct MetricCard: View {
    let title: String; let value: String; let icon: String; let color: Color
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundColor(color)
            Text(value).font(.headline).fontWeight(.bold).minimumScaleFactor(0.6).lineLimit(1)
            Text(title).font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center).lineLimit(2)
        }
        .padding(10).frame(maxWidth: .infinity)
        .background(color.opacity(0.08)).cornerRadius(12)
    }
}

// MARK: - Simple Bar Chart

private struct BarChartView: View {
    let data: [(String, Double)]

    private var maxValue: Double { data.map { $0.1 }.max() ?? 1 }

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(data.indices, id: \.self) { idx in
                    let item = data[idx]
                    let barH = maxValue > 0 ? (item.1 / maxValue) * (geo.size.height - 30) : 0
                    VStack(spacing: 2) {
                        Spacer()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.orange)
                            .frame(height: max(barH, 2))
                        Text(item.0).font(.system(size: 8)).foregroundColor(.secondary)
                            .lineLimit(1).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}
