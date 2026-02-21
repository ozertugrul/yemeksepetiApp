import SwiftUI

// MARK: - GuestLoginScreen
// Shown to anonymous (guest) users in place of protected content.
// Works both as a full-page tab replacement and as a sheet modal.

struct GuestLoginScreen: View {

    enum Context {
        case profile   // Profile tab — full page inside existing NavigationView
        case checkout  // Cart checkout — shown as a dismissible sheet
    }

    @ObservedObject var viewModel: AppViewModel
    var context: Context = .profile

    @State private var showingLogin    = false
    @State private var showingRegister = false
    @Environment(\.dismiss) private var dismiss

    // Features that require an account — shown as a bulleted list
    private let features: [(String, String)] = [
        ("mappin.and.ellipse",              "Teslimat adresi kaydetme"),
        ("creditcard.fill",                 "Kart bilgilerini saklama"),
        ("bag.fill",                        "Sipariş geçmişi ve takip"),
        ("tag.fill",                        "İndirim kuponları"),
        ("bell.fill",                       "Sipariş bildirimleri"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // ── Illustration ─────────────────────────────────────────
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.10))
                        .frame(width: 160, height: 160)
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 68))
                        .symbolRenderingMode(.multicolor)
                        .foregroundColor(.orange)
                }
                .padding(.top, 48)

                // ── Headline ──────────────────────────────────────────────
                VStack(spacing: 8) {
                    Text("Üye Girişi Gerekli")
                        .font(.title2).fontWeight(.bold)

                    Text(context == .checkout
                         ? "Sipariş verebilmek için giriş yapmanız veya üye olmanız gerekiyor."
                         : "Tüm özelliklere erişmek için giriş yapın veya ücretsiz üye olun.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 24)

                // ── Feature list ─────────────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(features, id: \.0) { icon, label in
                        HStack(spacing: 12) {
                            Image(systemName: icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.orange)
                                .frame(width: 28)
                            Text(label)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(20)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .padding(.horizontal, 24)
                .padding(.top, 28)

                // ── Buttons ───────────────────────────────────────────────
                VStack(spacing: 12) {
                    // Primary: Login
                    Button { showingLogin = true } label: {
                        Text("Giriş Yap")
                            .font(.headline).foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.orange)
                            .cornerRadius(14)
                    }

                    // Secondary: Register
                    Button { showingRegister = true } label: {
                        Text("Üye Ol")
                            .font(.headline).foregroundColor(.orange)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.orange, lineWidth: 1.5)
                            )
                    }

                    // Dismiss option for sheet context
                    if context == .checkout {
                        Button { dismiss() } label: {
                            Text("Şimdi değil")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(context == .profile ? "Hesabım" : "Giriş Gerekli")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingLogin) {
            LoginView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingRegister) {
            RegisterView(viewModel: viewModel)
        }
    }
}
