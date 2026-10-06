import AppKit
import ReviewWire
import SwiftUI

/// Havooch › About Havooch: the standard About panel, which shows the app
/// icon (`CFBundleIconFile`), the name and the version, with a line on
/// where the name comes from as its credits.
enum AboutPanel {
    /// The credits under the version.
    static let credits = "Named after Havuç, my orange-and-white cat. Say it hah-VOOCH."

    /// Shows the panel, or brings it to the front. From the menu the app
    /// comes forward with it; for a capture it doesn't, so an agent's
    /// screenshot never takes the focus from the person.
    static func show(activating: Bool = true) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let text = NSAttributedString(string: credits, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .paragraphStyle: style,
        ])
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        if activating { NSApp.activate() }
        // The build number is the version: an empty one keeps "(0.3.0)" off.
        NSApp.orderFrontStandardAboutPanel(options: [.credits: text, .version: ""])
        // AppKit makes the panel on first use and has no public way to it:
        // it's the window that wasn't there before.
        if let made = NSApp.windows.first(where: { !before.contains(ObjectIdentifier($0)) }) { panel = made }
    }

    /// The panel AppKit made, once it's been shown.
    private static weak var panel: NSWindow?

    /// The panel while it's on screen.
    static var window: NSWindow? {
        guard let panel, panel.isVisible else { return nil }
        return panel
    }

    /// Shows the panel and waits, up to two seconds, until it's on screen,
    /// for app control's `screenshot --window about`.
    static func showForCapture() async throws(AppRefusal) {
        if window == nil { show(activating: false) }
        for _ in 0..<40 where window == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard window != nil else { throw AppRefusal("the About panel didn't open") }
    }
}

/// The app menu's About item, with the credits.
struct AboutCommand: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppIdentity.appName)") {
                AboutPanel.show()
            }
        }
    }
}
