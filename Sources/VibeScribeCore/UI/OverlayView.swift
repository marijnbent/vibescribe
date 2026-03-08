import AppKit
import SwiftUI

struct OverlayView: View {
    @ObservedObject var appState: AppState
    @State private var pulse = false
    @State private var appear = false
    @State private var shimmer = false

    private var isEnhancing: Bool { appState.overlayLabel == "Enhancing" }

    var body: some View {
        HStack(spacing: 8) {
            PulseOrb(pulse: pulse, enhancing: isEnhancing)

            if let appIcon = appState.overlayAppIcon {
                OverlayAppIcon(icon: appIcon)
            }

            if isEnhancing {
                SparkleStars()
            } else {
                MiniWaveform(level: appState.audioLevel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .background(cardBackground)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(cardBorder)
        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
        .scaleEffect(appear ? 1.0 : 0.7)
        .opacity(appear ? 1.0 : 0.0)
        .blur(radius: appear ? 0 : 6)
        .offset(y: appear ? 0 : -20)
        .overlay(shimmerOverlay)
        .mask(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
        )
        .id(appState.overlayPulseID)
        .onAppear {
            pulse = appState.overlayVisible
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72, blendDuration: 0.2)) {
                appear = appState.overlayVisible
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
        .onDisappear {
            appear = false
            pulse = false
            shimmer = false
        }
        .onChange(of: appState.overlayVisible) { visible in
            pulse = visible
            if visible {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.72, blendDuration: 0.2)) {
                    appear = true
                }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            } else {
                shimmer = false
                withAnimation(.easeInOut(duration: 0.18)) {
                    appear = false
                }
            }
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.92), Color.black.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .opacity(0.2)
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.16), Color.white.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private var shimmerOverlay: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.0),
                Color.white.opacity(0.12),
                Color.white.opacity(0.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: 120, height: 120)
        .rotationEffect(.degrees(25))
        .offset(x: shimmer ? 120 : -140, y: shimmer ? -12 : 12)
        .blendMode(.screen)
    }
}

private struct OverlayAppIcon: View {
    let icon: NSImage

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .frame(width: 18, height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct MiniWaveform: View {
    let level: CGFloat

    private let barCount = 5
    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 2
    private let maxHeight: CGFloat = 20
    private let minHeight: CGFloat = 3
    private let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.45]

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(.white)
                    .frame(width: barWidth, height: barHeight(for: i))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func barHeight(for index: Int) -> CGFloat {
        minHeight + (maxHeight - minHeight) * level * weights[index]
    }
}

private struct SparkleStars: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            star(size: 10, opacity: 1.0, dx: 2.5, dy: -2, duration: 1.2)
            star(size: 7, opacity: 0.7, dx: -3, dy: 2.5, duration: 1.5)
            star(size: 6, opacity: 0.5, dx: 2, dy: 1.5, duration: 1.0)
        }
        .frame(width: 23, height: 20)
        .onAppear { animate = true }
    }

    private func star(size: CGFloat, opacity: Double, dx: CGFloat, dy: CGFloat, duration: Double) -> some View {
        StarShape()
            .fill(.white.opacity(opacity))
            .frame(width: size, height: size)
            .offset(x: animate ? dx : -dx, y: animate ? dy : -dy)
            .animation(
                .easeInOut(duration: duration).repeatForever(autoreverses: true),
                value: animate
            )
    }
}

private struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.38
        var path = Path()
        for i in 0..<8 {
            let angle = Double(i) * .pi / 4 - .pi / 2
            let r = i.isMultiple(of: 2) ? outer : inner
            let pt = CGPoint(x: center.x + CGFloat(cos(angle)) * r,
                             y: center.y + CGFloat(sin(angle)) * r)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}

private struct PulseOrb: View {
    let pulse: Bool
    var enhancing: Bool = false

    var body: some View {
        ZStack {
            if enhancing {
                Circle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 9, height: 9)
            } else {
                Circle()
                    .fill(Color.red.opacity(0.25))
                    .frame(width: 22, height: 22)
                    .scaleEffect(pulse ? 1.15 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: pulse
                    )
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.red, Color.red.opacity(0.7)],
                            center: .center,
                            startRadius: 2,
                            endRadius: 12
                        )
                    )
                    .frame(width: 9, height: 9)
                    .shadow(color: Color.red.opacity(0.6), radius: 8, x: 0, y: 0)
            }
        }
        .frame(width: 22, height: 22)
    }
}
