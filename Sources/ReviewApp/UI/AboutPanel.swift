import AppKit
import ReviewWire
import SwiftUI

enum AboutPanel {
    static let credits = "Named after Havuç, my orange-and-white cat. Say it hah-VOOCH."

    static func show(activating: Bool = true) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let text = NSAttributedString(string: credits, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .paragraphStyle: style,
        ])
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        if activating { NSApp.activate() }
        NSApp.orderFrontStandardAboutPanel(options: [.credits: text, .version: ""])
        if let made = NSApp.windows.first(where: { !before.contains(ObjectIdentifier($0)) }) { panel = made }
    }

    private static weak var panel: NSWindow?

    static var window: NSWindow? {
        guard let panel, panel.isVisible else { return nil }
        return panel
    }

    static func showForCapture() async throws(AppRefusal) {
        if window == nil { show(activating: false) }
        for _ in 0..<40 where window == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard window != nil else { throw AppRefusal("the About panel didn't open") }
    }
}

struct AboutCommand: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppIdentity.appName)") {
                AboutPanel.show()
            }
        }
    }
}
