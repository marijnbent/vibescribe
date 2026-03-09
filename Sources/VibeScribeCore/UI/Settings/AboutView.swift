import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("VibeScribe")
                .font(.title)
                .fontWeight(.semibold)
            Text("Voice-to-text for macOS")
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Link("GitHub: marijnbent/vibescribe", destination: URL(string: "https://github.com/marijnbent/vibescribe")!)
                    .foregroundStyle(.tint)
                Link("Forked from: flatoy/vibescribe", destination: URL(string: "https://github.com/flatoy/vibescribe")!)
                    .foregroundStyle(.tint)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
