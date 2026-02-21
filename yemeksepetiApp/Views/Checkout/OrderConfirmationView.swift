import SwiftUI

// MARK: - OrderConfirmationView

struct OrderConfirmationView: View {
    let order: Order
    @ObservedObject var cart: CartViewModel
    var onComplete: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // ── Success Animation ───────────────────────────────
                    VStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.green.opacity(0.12)).frame(width: 100, height: 100)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60)).foregroundColor(.green)
                        }
                        Text("Siparişiniz Alındı!").font(.title2).fontWeight(.bold)
                        Text("Mağaza siparişinizi kısa süre içinde onaylayacak.")
                            .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)

                    // ── Pickup Code (if applicable) ──────────────────────
                    if let pickupCode = order.pickupCode {
                        VStack(spacing: 8) {
                            Text("Teslim Alma Kodunuz").font(.caption).foregroundColor(.secondary).textCase(.uppercase)
                            Text(pickupCode)
                                .font(.system(size: 48, weight: .bold, design: .monospaced))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 24).padding(.vertical, 12)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(16)
                            Text("Mağazaya gittiğinizde bu kodu gösterin.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(14)
                        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                        .padding(.horizontal)
                    }

                    // ── Order Info ───────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sipariş Bilgileri").font(.headline).padding(.horizontal)

                        infoCard {
                            infoRow("Sipariş No", "#\(order.id.prefix(8).uppercased())")
                            Divider()
                            infoRow("Mağaza", order.restaurantName)
                            Divider()
                            infoRow("Tarih", order.formattedDate)
                            Divider()
                            infoRow("Ödeme", order.paymentMethod.displayName)
                            if let addr = order.deliveryAddress {
                                Divider()
                                infoRow("Adres", addr.fullAddress)
                                if !addr.phone.isEmpty {
                                    Divider()
                                    infoRow("İletişim", addr.phone)
                                }
                            }
                        }
                    }

                    // ── Order Summary ─────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ürünler").font(.headline).padding(.horizontal)

                        infoCard {
                            ForEach(order.items) { item in
                                HStack {
                                    Text("\(item.quantity)x \(item.name)").font(.subheadline)
                                    Spacer()
                                    Text("₺\(String(format: "%.2f", item.lineTotal))")
                                        .font(.subheadline).foregroundColor(.secondary)
                                }
                                if !item.optionSummary.isEmpty {
                                    Text(item.optionSummary).font(.caption).foregroundColor(.secondary)
                                        .padding(.leading, 4)
                                }
                                if item.id != order.items.last?.id { Divider() }
                            }
                            Divider()
                            HStack {
                                Text("Toplam").fontWeight(.bold)
                                Spacer()
                                Text("₺\(String(format: "%.2f", order.total))")
                                    .fontWeight(.bold).foregroundColor(.orange)
                            }
                        }
                    }

                    // ── Note ─────────────────────────────────────────────
                    if let note = order.note, !note.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sipariş Notu").font(.caption).foregroundColor(.secondary)
                                .padding(.horizontal)
                            Text(note).font(.subheadline).padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6)).cornerRadius(10)
                                .padding(.horizontal)
                        }
                    }

                    Spacer(minLength: 20)
                }
            }

            // ── Bottom Button ─────────────────────────────────────────────
            VStack(spacing: 0) {
                Divider()
                Button {
                    cart.clear()
                    onComplete()
                } label: {
                    Text("Ana Sayfaya Dön")
                        .font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.orange)
                        .cornerRadius(14)
                        .padding()
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
    }

    // ── Helper ────────────────────────────────────────────────────────────

    private func infoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) { content() }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
            .padding(.horizontal)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.subheadline).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
    }
}
