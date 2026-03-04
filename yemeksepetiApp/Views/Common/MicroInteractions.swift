import SwiftUI

enum AppMotion {
    static let quick: Animation = .easeOut(duration: 0.16)
    static let standard: Animation = .easeInOut(duration: 0.24)
    static let spring: Animation = .interactiveSpring(response: 0.32, dampingFraction: 0.84)
}

struct PressScaleButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(AppMotion.quick, value: configuration.isPressed)
    }
}

extension View {
    func subtleCardTransition() -> some View {
        transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity
        ))
    }
}
