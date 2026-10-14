import ReviewWire
import SwiftUI

struct CompareStage: View {
    let model: WindowModel
    let pair: PlayerPair
    let session: CompareSession

    @State private var paneAreas: [CompareSide: CGRect] = [:]

    var body: some View {
        Group {
            switch session.layout {
            case .sideBySide: sideBySide
            case .flip: flip
            case .slider: slider
            }
        }
        .overlay { Notices(model: model) }
        .onChange(of: model.activeSide) { keepArea() }
    }

    private var sideBySide: some View {
        HStack(spacing: 6) {
            ForEach(CompareSide.allCases, id: \.self) { side in
                ZStack(alignment: .topLeading) {
                    StagePane(model: model, engine: pair.engine(side), side: side)
                    label(side)
                    if model.activeSide == side {
                        StagePopoverLayer(model: model)
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { area in
                    paneAreas[side] = area
                    keepArea()
                }
            }
        }
    }

    private func keepArea() {
        guard session.layout == .sideBySide, let side = model.activeSide, let area = paneAreas[side] else { return }
        model.stageArea = area
    }

    private var flip: some View {
        ZStack(alignment: .topLeading) {
            ForEach(CompareSide.allCases, id: \.self) { side in
                let shows = session.showing == side
                StagePane(model: model, engine: pair.engine(side), side: side)
                    .opacity(shows ? 1 : 0)
                    .allowsHitTesting(shows)
            }
            label(session.showing)
            StagePopoverLayer(model: model)
        }
        .overlay(alignment: .bottom) {
            FlipBar(model: model, session: session)
                .padding(10)
        }
    }

    private var slider: some View {
        GeometryReader { proxy in
            let split = proxy.size.width * session.slider
            ZStack(alignment: .topLeading) {
                StagePane(model: model, engine: pair.engine(.right), side: .right)
                StagePane(model: model, engine: pair.engine(.left), side: .left, hitWidth: split)
                    .mask(alignment: .leading) { Rectangle().frame(width: split) }
                StagePopoverLayer(model: model)
                SliderHandle(model: model, split: split, width: proxy.size.width)
                label(.left)
                label(.right)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func label(_ side: CompareSide) -> some View {
        let number = session.number(side)
        return SideLabel(
            side: CompareSession.name(of: side, in: session.layout), number: number,
            label: model.versionSwitch?.entry(number)?.label, isActive: model.activeSide == side
        )
        .padding(8)
    }
}

private struct SideLabel: View {
    let side: String
    let number: Int
    let label: String?
    let isActive: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 5) {
            Text(side.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .opacity(0.75)
            Text("v\(number)")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
            if let label {
                Text(label).font(.system(size: 11.5)).lineLimit(1)
            }
        }
        .foregroundStyle(palette[isActive ? .textOnAccent : .sizeLabel])
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(palette[isActive ? .accentFill : .regionDim]))
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(side) side, v\(number)\(label.map { ", \($0)" } ?? "")\(isActive ? ", new messages go here" : "")")
    }
}

private struct FlipBar: View {
    let model: WindowModel
    let session: CompareSession
    @Environment(\.palette) private var palette

    var body: some View {
        let showsRight = session.showing == .right
        Button {
            model.flipCompare()
        } label: {
            HStack(spacing: 6) {
                Text("v\(session.number(.left))").fontWeight(showsRight ? .regular : .bold)
                CompareKeyCap(text: "\\")
                Text("v\(session.number(.right))").fontWeight(showsRight ? .bold : .regular)
                Text("press to flip").opacity(0.75)
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(palette[.sizeLabel])
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(palette[.regionDim]))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Flip to the other version (\\)")
        .accessibilityLabel("Flip to v\(session.number(showsRight ? .left : .right))")
    }
}

private struct SliderHandle: View {
    let model: WindowModel
    let split: CGFloat
    let width: CGFloat
    @Environment(\.palette) private var palette

    private static let grip: CGFloat = 14

    var body: some View {
        ZStack {
            Rectangle()
                .fill(palette[.knob])
                .frame(width: 2)
                .shadow(color: palette[.shadow], radius: 1)
            Circle()
                .fill(palette[.knob])
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette[.textSecondary])
                }
                .shadow(color: palette[.shadow], radius: 2)
        }
        .frame(width: Self.grip * 2)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .offset(x: split - Self.grip)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                .onChanged { drag in
                    guard width > 0 else { return }
                    model.slideCompare(to: drag.location.x / width)
                }
        )
        .pointerStyle(.columnResize)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coordinateSpace(.named(Self.space))
        .accessibilityElement()
        .accessibilityLabel("Slider")
        .accessibilityValue("\(Int((split / max(width, 1) * 100).rounded())) percent shows the left side")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.05 : -0.05
            model.slideCompare(to: split / max(width, 1) + step)
        }
    }

    private static let space = "compare-slider"
}

struct CompareKeyCap: View {
    let text: String
    @Environment(\.palette) private var palette

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium).monospaced())
            .foregroundStyle(palette[.textSecondary])
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(RoundedRectangle(cornerRadius: 4).fill(palette[.well]))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(palette[.popoverBorder]))
    }
}
