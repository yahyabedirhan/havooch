import AppKit
import ReviewCore
import SwiftUI

enum AgentLogoImage {
    static let folder: URL? = {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("AgentLogos", isDirectory: true)
        if let bundled, FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Packaging/AgentLogos", isDirectory: true)
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }()

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

struct AgentAvatar: View {
    let agent: KnownAgent?
    let size: CGFloat
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
