import SwiftUI

/// Warp-inspired subtle activity indicator with smooth rotation animation.
/// Uses the accent color and maintains a lightweight visual presence.
struct ActivityIndicator: View {
    let isAnimating: Bool
    var size: CGFloat = 16

    @Environment(\.adaptiveTheme) private var theme
    @State private var rotation: Double = 0

    var body: some View {
        if isAnimating {
            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(
                    theme.accentC.opacity(0.7),
                    style: StrokeStyle(lineWidth: max(size / 8, 1.5), lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.5)))
        }
    }
}

/// Dot-based loading indicator (alternative for inline use)
struct DotActivityIndicator: View {
    let isAnimating: Bool

    @Environment(\.adaptiveTheme) private var theme
    @State private var activeDot = 0
    @State private var dotTimer: Timer?

    var body: some View {
        if isAnimating {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(theme.accentC.opacity(activeDot == index ? 1.0 : 0.3))
                        .frame(width: 4, height: 4)
                        .scaleEffect(activeDot == index ? 1.2 : 1.0)
                }
            }
            .onAppear { startDotCycle() }
            .onDisappear {
                dotTimer?.invalidate()
                dotTimer = nil
            }
        }
    }

    private func startDotCycle() {
        dotTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                activeDot = (activeDot + 1) % 3
            }
        }
    }
}
