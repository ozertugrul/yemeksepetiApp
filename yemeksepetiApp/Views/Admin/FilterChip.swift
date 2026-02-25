import SwiftUI

/// Yeniden kullanılabilir filtre chip bileşeni — Admin panelde filtreleme için
struct FilterChip: View {
    let label: String
    let isActive: Bool
    var color: Color = .gray
    var count: Int? = nil
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(label)
                    .font(.caption)
                    .fontWeight(isActive ? .semibold : .regular)
                if let count {
                    Text("(\(count))")
                        .font(.caption2)
                        .foregroundColor(isActive ? color.opacity(0.8) : .secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? color.opacity(0.15) : Color(.systemGray6))
            .foregroundColor(isActive ? color : .primary)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isActive ? color.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - iOS 15 uyumu
extension View {
    @ViewBuilder
    func if_iOS16_presentationDetents() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.medium, .large])
        } else {
            self
        }
    }
}
