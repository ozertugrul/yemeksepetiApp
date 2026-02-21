import SwiftUI

// MARK: - OrderReviewSheet

struct OrderReviewSheet: View {
    let order: Order
    @ObservedObject var viewModel: AppViewModel
    var onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var speedRating: Double = 0
    @State private var tasteRating: Double = 0
    @State private var presentationRating: Double = 0
    @State private var comment: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var isValid: Bool {
        speedRating > 0 && tasteRating > 0 && presentationRating > 0
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 52)).foregroundColor(.orange)
                        Text("Siparişinizi Değerlendirin")
                            .font(.title3).fontWeight(.bold)
                        Text(order.restaurantName)
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.top, 20)

                    Divider()

                    // Rating categories
                    VStack(spacing: 20) {
                        RatingCategory(
                            title: "Hız",
                            subtitle: "Teslimat hızı nasıldı?",
                            icon: "bolt.fill",
                            rating: $speedRating
                        )
                        Divider()
                        RatingCategory(
                            title: "Lezzet",
                            subtitle: "Siparişiniz lezzetli miydi?",
                            icon: "fork.knife",
                            rating: $tasteRating
                        )
                        Divider()
                        RatingCategory(
                            title: "Sunum",
                            subtitle: "Paketleme ve sunum nasıldı?",
                            icon: "shippingbox.fill",
                            rating: $presentationRating
                        )
                    }
                    .padding(.horizontal)

                    Divider()

                    // Comment
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Yorum (isteğe bağlı)").font(.subheadline).fontWeight(.semibold)
                        TextEditor(text: $comment)
                            .frame(minHeight: 80)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)

                    if let error = errorMessage {
                        Text(error).font(.caption).foregroundColor(.red).padding(.horizontal)
                    }

                    // Submit button
                    Button {
                        submitReview()
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "paperplane.fill")
                                Text("Değerlendirmeyi Gönder")
                            }
                        }
                        .font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(isValid ? Color.orange : Color.gray)
                        .cornerRadius(14)
                    }
                    .disabled(!isValid || isSubmitting)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Değerlendirme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Atla") { dismiss() }
                }
            }
        }
    }

    private func submitReview() {
        isSubmitting = true
        errorMessage = nil

        let review = OrderReview(
            orderId: order.id,
            restaurantId: order.restaurantId,
            userId: order.userId,
            speedRating: speedRating,
            tasteRating: tasteRating,
            presentationRating: presentationRating,
            comment: comment
        )

        // Dummy restaurant for updating (just id is needed)
        let dummyRestaurant = Restaurant(
            id: order.restaurantId, name: order.restaurantName, description: "",
            cuisineType: "", rating: 0, deliveryTime: "", minOrderAmount: 0,
            menu: [], isActive: true
        )

        viewModel.orderService.submitReview(review, restaurant: dummyRestaurant) { error in
            isSubmitting = false
            if let error {
                errorMessage = error.localizedDescription
            } else {
                onComplete()
                dismiss()
            }
        }
    }
}

// MARK: - RatingCategory

private struct RatingCategory: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var rating: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline).fontWeight(.semibold)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if rating > 0 {
                    Text(ratingLabel(rating)).font(.caption).fontWeight(.semibold)
                        .foregroundColor(.orange)
                }
            }
            StarRatingPicker(rating: $rating)
        }
    }

    private func ratingLabel(_ r: Double) -> String {
        switch Int(r) {
        case 1: return "Çok Kötü"
        case 2: return "Kötü"
        case 3: return "Orta"
        case 4: return "İyi"
        case 5: return "Mükemmel"
        default: return ""
        }
    }
}

// MARK: - StarRatingPicker

struct StarRatingPicker: View {
    @Binding var rating: Double

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: Double(star) <= rating ? "star.fill" : "star")
                    .font(.title2)
                    .foregroundColor(Double(star) <= rating ? .orange : Color(.systemGray4))
                    .onTapGesture { rating = Double(star) }
            }
        }
    }
}
