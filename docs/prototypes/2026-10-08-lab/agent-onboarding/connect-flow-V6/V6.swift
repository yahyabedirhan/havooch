import LabHost
import SwiftUI

/// V6 (from V4): V1's experience (two header buttons, one connect view) in a new look.
public let variant = LabVariant(window: LabWindow(titleVisibility: .hidden, titlebarAppearsTransparent: true)) {
    Themed { V4View() }
}

struct V4View: View {
    @State private var m = Onboard()

    var body: some View {
        WindowShell(m: m) {
            if m.showsTourButton {
                TourButton(m: m)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        } grouped: {
            GroupButton(
                symbol: "antenna.radiowaves.left.and.right",
                isOn: m.page == .connect,
                id: "connectButton",
                help: m.setupComplete ? "Connect an agent" : "Connect an agent: \(m.remaining) to do"
            ) {
                if !m.setupComplete { AmberDot() }
            } action: {
                m.page == .connect ? m.back() : m.openConnect()
            }
        } overlay: { _ in
            EmptyView()
        }
        .animation(.easeOut(duration: 0.2), value: m.showsTourButton)
    }
}

/// "Finish setup" with the count of setup items left; opens the tour.
private struct TourButton: View {
    let m: Onboard
    @State private var hover = false
    @Environment(\.tok) private var t

    var body: some View {
        Button { m.toggleTour() } label: {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                Text("Finish setup")
                    .font(.callout.weight(.medium))
                if m.remaining > 0 {
                    Text("\(m.remaining)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(t.textOnAccent)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(t.amber, in: Circle())
                }
            }
            .foregroundStyle(m.tourOpen ? t.accent : t.textPrimary)
            .padding(.leading, 10)
            .padding(.trailing, m.remaining > 0 ? 6 : 10)
            .frame(height: 34)
            .background(.regularMaterial, in: Capsule())
            .background(m.tourOpen || hover ? t.controlHover : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(m.tourOpen ? t.accent.opacity(0.5) : t.popoverBorder, lineWidth: m.tourOpen ? 1 : 0.5))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .labID("tourButton")
        .help("Take the setup tour")
    }
}
