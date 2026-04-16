import AppKit
import SwiftUI

struct OverlayView: View {
    @ObservedObject var sessionState: SessionState
    @State private var pulse = false
    @State private var appear = false

    private var isEnhancing: Bool { sessionState.overlayLabel == "Enhancing" }
    private let cardCornerRadius: CGFloat = 14

    var body: some View {
        HStack(spacing: 10) {
            PulseOrb(pulse: pulse, enhancing: isEnhancing)

            if let appIcon = sessionState.overlayAppIcon {
                OverlayAppIcon(icon: appIcon)
            }

            if isEnhancing {
                SparkleStars()
            } else {
                MiniWaveform(level: sessionState.audioLevel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(cardBorder)
        .scaleEffect(appear ? 1.0 : 0.96)
        .opacity(appear ? 1.0 : 0.0)
        .offset(y: appear ? 0 : -8)
        .id(sessionState.overlayPulseID)
        .onAppear {
            pulse = sessionState.overlayVisible
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72, blendDuration: 0.2)) {
                appear = sessionState.overlayVisible
            }
        }
        .onDisappear {
            appear = false
            pulse = false
        }
        .onChange(of: sessionState.overlayVisible) { visible in
            pulse = visible
            if visible {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.72, blendDuration: 0.2)) {
                    appear = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.18)) {
                    appear = false
                }
            }
        }
    }

    private var cardBackground: some View {
        OverlayGlassBackground(cornerRadius: cardCornerRadius)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.34), Color.white.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}

private struct VisualEffectBackdropView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            ? .windowBackground
            : material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

private struct OverlayGlassBackground: View {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    private var tintOpacity: Double {
        if reduceTransparency {
            return 0.95
        }

        return colorScheme == .dark ? 0.24 : 0.16
    }

    private var highlightOpacity: Double {
        if reduceTransparency {
            return 0.04
        }

        return colorScheme == .dark ? 0.18 : 0.24
    }

    var body: some View {
        ZStack {
            VisualEffectBackdropView(material: .hudWindow)

            Color(NSColor.windowBackgroundColor)
                .opacity(tintOpacity)

            LinearGradient(
                colors: [
                    Color.white.opacity(highlightOpacity),
                    Color.white.opacity(0.06),
                    Color.white.opacity(0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(reduceTransparency ? 0 : 0.14),
                    Color.white.opacity(0)
                ],
                center: .topLeading,
                startRadius: 4,
                endRadius: 56
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
                    .fill(Color.white.opacity(0.92))
                    .frame(width: barWidth, height: barHeight(for: i))
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
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
