import ReviewCore
import SwiftUI

enum Metrics {
    static let stageMinimumWidth: CGFloat = 480
    static let windowMinimumHeight: CGFloat = 480
    static let sidebarWidth: CGFloat = 340
    static let sidebarWidthRange: ClosedRange<CGFloat> = 300...460

    static func windowMinimumWidth(sidebarShown: Bool) -> CGFloat {
        stageMinimumWidth + (sidebarShown ? sidebarWidthRange.lowerBound : 0)
    }

    static func sidebarWidth(preferred: CGFloat, windowWidth: CGFloat) -> CGFloat {
        let maximum = sidebarMaximumWidth(windowWidth: windowWidth)
        return min(max(preferred, sidebarWidthRange.lowerBound), maximum)
    }

    static func sidebarMaximumWidth(windowWidth: CGFloat) -> CGFloat {
        max(sidebarWidthRange.lowerBound, min(sidebarWidthRange.upperBound, windowWidth - stageMinimumWidth))
    }
    static let gutter: CGFloat = 12
    static let stageCorner: CGFloat = 12
    static let barHeight: CGFloat = 52
    static let barPadding: CGFloat = 16
    static let sidebarPadding: CGFloat = 16
}

enum StateLook {
    static func pinGlyph(_ state: MessageState) -> String? {
        switch state {
        case .queued, .sent: nil
        case .acknowledged, .done: "checkmark"
        case .working: "ellipsis"
        case .failed: "xmark"
        }
    }

    static func glyph(_ state: MessageState) -> String {
        switch state {
        case .queued: "circle.dashed"
        case .sent: "arrow.up.circle.fill"
        case .acknowledged: "checkmark.circle"
        case .working: "ellipsis.circle.fill"
        case .done: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    static func name(_ state: MessageState) -> String {
        switch state {
        case .queued: "Queued"
        case .sent: "Sent"
        case .acknowledged: "Acknowledged"
        case .working: "Working"
        case .done: "Done"
        case .failed: "Failed"
        }
    }
}
