import AppKit
import ReviewCore
import SwiftUI

/// Loads a known agent's logo from the bundled `AgentLogos` (vector PDFs,
/// from the makers' SVGs by `make agent-logos`). Ported from Shipyard
/// (`yahyabedirhan/shipyard` at `74b9695`).
enum AgentLogoImage {
    /// The logos: in the app bundle's resources (`make bundle` copies
    /// `Packaging/AgentLogos/` there, as it copies the themes), or in the
    /// source tree's `Packaging/AgentLogos/` for a build that isn't bundled
    /// (`swift test`, `swift run`).
    static let folder: URL? = {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("AgentLogos", isDirectory: true)
        if let bundled, FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Packaging/AgentLogos", isDirectory: true)
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }()

    /// The agent's logo for light or dark mode: a `.template` logo comes back
    /// as a template image, for the view to tint. `nil` when the folder lacks
    /// the file.
    static func image(for agent: KnownAgent, dark: Bool) -> NSImage? {
        let logo = agent.logo
        let name = logo.look == .lightAndDark && dark ? logo.resource + "-dark" : logo.resource
        if let cached = cache[name] { return cached }
        guard let url = folder?.appendingPathComponent(name + ".pdf", isDirectory: false),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = logo.look == .template
        cache[name] = image
        return image
    }

    private static var cache: [String: NSImage] = [:]
}

/// A known agent's mark: its logo, fitted to a square of any `size` with
/// the corners an app icon has; a one-colour glyph is tinted like text, and
/// a logo with a dark-mode file switches to it. Decoration: the agent's
/// name beside it says who it is.
struct AgentMark: View {
    let agent: KnownAgent
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if let image = AgentLogoImage.image(for: agent, dark: colorScheme == .dark) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .foregroundStyle(palette[.textPrimary])
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// The agent's avatar: its logo when the listener session names a known
/// agent, else `symbol` in a disc of `fill`, the neutral mark an unknown
/// harness gets. Any size.
struct AgentAvatar: View {
    let agent: KnownAgent?
    let size: CGFloat
    /// The SF Symbol shown without a logo: "sparkles" for an agent's
    /// message, "person.fill" for the person's.
    let symbol: String
    let fill: Color
    @Environment(\.palette) private var palette

    var body: some View {
        if let agent {
            AgentMark(agent: agent, size: size)
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(palette[.textOnAccent])
                .frame(width: size, height: size)
                .background(fill, in: Circle())
                .accessibilityHidden(true)
        }
    }
}
