import ReviewWire
import SwiftUI

/// The header's Compare button (compare-control V4 "Live search
/// picker"): it opens the compare popover, a two-pane mini window of what
/// the screen will show. Shown in a project of two versions or more.
struct CompareButton: View {
    let model: WindowModel
    @Environment(\.palette) private var palette

    var body: some View {
        let isOpen = model.compare?.phase == .choosing
        Button {
            model.toggleCompare()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: CompareSession.symbol(.sideBySide))
                    .font(.system(size: 11, weight: .medium))
                Text("Compare")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(palette[isOpen ? .accent : .textPrimary])
            .padding(.horizontal, 9)
            .frame(minHeight: 24)
            .background(Capsule().fill(palette[isOpen ? .controlHover : .well]))
            .overlay(Capsule().strokeBorder(palette[.popoverBorder]))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pressedByKeys(in: model) { model.toggleCompare() }
        .help("Compare two versions")
        .popover(isPresented: popoverShown, arrowEdge: .bottom) {
            ComparePopover(model: model)
                .tint(palette[.accent])
                .popoverSurface(palette)
        }
    }

    /// Open while the model's popover is; closing it is Cancel.
    private var popoverShown: Binding<Bool> {
        Binding(
            get: { model.compare?.phase == .choosing },
            set: { if !$0, model.compare?.phase == .choosing { model.exitCompare() } }
        )
    }
}

/// The header while the window compares: the two versions on a filled
/// capsule with the layout's icon, and Exit Compare with its key.
struct ComparingBadge: View {
    let model: WindowModel
    let session: CompareSession
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: CompareSession.symbol(session.layout))
                    .font(.system(size: 11, weight: .medium))
                Text("v\(session.number(.left)) · v\(session.number(.right))")
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(palette[.textOnAccent])
            .padding(.horizontal, 10)
            .frame(minHeight: 24)
            .background(Capsule().fill(palette[.accentFill]))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Comparing v\(session.number(.left)) and v\(session.number(.right)), \(CompareSession.words(session.layout))")
            Button {
                model.exitCompare()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    Text("Exit Compare").font(.system(size: 11.5, weight: .medium))
                    CompareKeyCap(text: "esc")
                }
                .foregroundStyle(palette[.textPrimary])
                .padding(.leading, 9)
                .padding(.trailing, 4)
                .frame(minHeight: 24)
                .background(Capsule().fill(palette[.well]))
                .overlay(Capsule().strokeBorder(palette[.popoverBorder]))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .pressedByKeys(in: model) { model.exitCompare() }
            .help("Back to one version (Escape)")
            .accessibilityLabel("Exit Compare")
        }
    }
}

/// The compare popover: the title, the layout's segments, the mini window
/// with a chip per side and the swap button between them, and the
/// footer with the opening note, Cancel and the action.
private struct ComparePopover: View {
    let model: WindowModel
    /// The playhead's time when the popover opened: the mini window's
    /// pictures are of that moment.
    @State private var time: Double
    @Environment(\.palette) private var palette

    init(model: WindowModel) {
        self.model = model
        _time = State(initialValue: model.engine.time)
    }

    var body: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Compare two versions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette[.textPrimary])
                Text("Pick a layout, then click a side to pick its version.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette[.textSecondary])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let session = model.compare {
                LayoutPicker(model: model, layout: session.layout)
                MiniWindow(model: model, session: session, time: time)
                footer(session)
            }
        }
        .padding(14)
        .frame(width: 440)
    }

    private func footer(_ session: CompareSession) -> some View {
        HStack(spacing: 8) {
            if let opening = model.compareOpening {
                Text("Opens on v\(opening.number(.left)) and v\(opening.number(.right))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette[.textTertiary])
            }
            Spacer()
            Button("Cancel") { model.exitCompare() }
                .keyboardShortcut(.cancelAction)
            Button {
                model.startCompareForPerson()
            } label: {
                Text(session.action).fontWeight(.semibold)
            }
            .filledButton(palette)
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
    }
}

/// Side by side, Flip and Slider, as a segmented row of icon and words.
private struct LayoutPicker: View {
    let model: WindowModel
    let layout: CompareLayout
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CompareLayout.allCases, id: \.self) { each in
                let on = each == layout
                Button {
                    model.changeCompareForPerson(CompareChange(layout: each))
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: CompareSession.symbol(each)).font(.system(size: 11))
                        Text(CompareSession.words(each)).font(.system(size: 11.5, weight: on ? .semibold : .regular))
                    }
                    .foregroundStyle(palette[on ? .textPrimary : .textSecondary])
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(palette[palette.theme.kind == .dark ? .popoverBorder : .knob])
                                .shadow(color: palette[.shadow].opacity(0.5), radius: 0.5, y: 0.5)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CompareSession.words(each))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(palette[.well]))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette[.popoverBorder]))
    }
}

/// The comparison window in miniature: a title strip, the two pictures in
/// the layout, a chip per side with the swap button between them, and
/// the shared playhead under it. A picture and a chip open their side's
/// picker.
private struct MiniWindow: View {
    let model: WindowModel
    let session: CompareSession
    let time: Double
    @Environment(\.palette) private var palette

    var body: some View {
        let duration = max(model.engine.duration, 0.001)
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(palette[.textTertiary].opacity(0.5)).frame(width: 5, height: 5)
                }
                Spacer()
            }
            preview
                .frame(height: 84)
            HStack(spacing: 6) {
                SideChip(model: model, session: session, side: .left, time: time)
                Button {
                    try? model.swapCompare()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette[.textSecondary])
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(palette[.well]))
                        .overlay(Circle().strokeBorder(palette[.popoverBorder]))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Swap sides")
                .accessibilityLabel("Swap sides")
                SideChip(model: model, session: session, side: .right, time: time)
            }
            GeometryReader { proxy in
                let along = proxy.size.width * min(max(time / duration, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(palette[.track]).frame(height: 3)
                    Capsule().fill(palette[.accent]).frame(width: along, height: 3)
                    Circle().fill(palette[.knob]).shadow(color: palette[.shadow], radius: 0.5).frame(width: 8, height: 8)
                        .offset(x: along - 4)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 8)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette[.well]))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette[.popoverBorder]))
    }

    @ViewBuilder private var preview: some View {
        switch session.layout {
        case .sideBySide:
            HStack(spacing: 4) {
                frame(.left)
                frame(.right)
            }
        case .flip:
            ZStack {
                frame(.right).opacity(0.8).scaleEffect(0.84).offset(x: 16, y: -7)
                frame(.left)
                    .shadow(color: palette[.shadow], radius: 3, y: 1)
                    .scaleEffect(0.84).offset(x: -12, y: 6)
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 3) {
                    CompareKeyCap(text: "\\")
                    Text("flips").font(.system(size: 9.5)).foregroundStyle(palette[.textSecondary])
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(palette[.popover]))
            }
        case .slider:
            GeometryReader { proxy in
                let split = proxy.size.width * session.slider
                ZStack(alignment: .leading) {
                    frame(.right)
                    frame(.left).mask(alignment: .leading) { Rectangle().frame(width: split) }
                    Rectangle().fill(palette[.knob]).frame(width: 1.5).offset(x: split - 0.75)
                    Circle().fill(palette[.knob]).frame(width: 12, height: 12)
                        .overlay {
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(palette[.textSecondary])
                        }
                        .offset(x: split - 6)
                }
            }
        }
    }

    /// A side's picture with its name and version on it; a click opens
    /// the side's picker.
    private func frame(_ side: CompareSide) -> some View {
        let number = session.number(side)
        let isOpen = session.picker?.side == side
        return VersionStill(model: model, number: number, time: time, corner: 4)
            .overlay(alignment: side == .left || session.layout == .flip ? .topLeading : .topTrailing) {
                Text("\(CompareSession.name(of: side, in: session.layout)) · v\(number)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(palette[.sizeLabel])
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(palette[.regionDim]))
                    .padding(3)
            }
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(isOpen ? palette[.accent] : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
            .onTapGesture { model.toggleComparePicker(side) }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(CompareSession.name(of: side, in: session.layout)) side, v\(number), pick its version")
            .accessibilityAction { model.toggleComparePicker(side) }
    }
}

/// A frame of the project's version `number` at `time`, made when it
/// first shows; the letterbox until then.
private struct VersionStill: View {
    let model: WindowModel
    let number: Int
    let time: Double
    var corner: CGFloat = 4
    @Environment(\.palette) private var palette

    var body: some View {
        let path = model.versionPath(number)
        ZStack {
            palette[.letterbox]
            if let path, let image = model.thumbnails.still(of: path, at: time) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .task(id: "\(path ?? "") \(time)") {
            if let path { await model.thumbnails.loadStill(of: path, at: time) }
        }
        .accessibilityHidden(true)
    }
}

/// A side's chip under the mini window: its name, the version and its
/// label, and a chevron; a click opens its picker, hung under it.
private struct SideChip: View {
    let model: WindowModel
    let session: CompareSession
    let side: CompareSide
    let time: Double
    @Environment(\.palette) private var palette

    var body: some View {
        let number = session.number(side)
        let entry = model.versionSwitch?.entry(number)
        let active = session.picker?.side == side
        Button {
            model.toggleComparePicker(side)
        } label: {
            HStack(spacing: 5) {
                Text(CompareSession.name(of: side, in: session.layout).uppercased())
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(palette[active ? .accent : .textTertiary])
                Text("v\(number)")
                    .font(.system(size: 11.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette[active ? .accent : .textPrimary])
                Text(entry?.label ?? "no label")
                    .font(.system(size: 11))
                    .foregroundStyle(palette[entry?.label == nil ? .textTertiary : .textSecondary])
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: active ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(palette[active ? .accent : .textTertiary])
            }
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(palette[active ? .controlHover : .popover]))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette[active ? .accent : .popoverBorder], lineWidth: active ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Pick the \(side.rawValue) side's version")
        .accessibilityLabel("\(CompareSession.name(of: side, in: session.layout)) side, v\(number), pick its version")
        .popover(isPresented: pickerShown, arrowEdge: .bottom) {
            ComparePickerPanel(model: model, side: side, time: time)
                .tint(palette[.accent])
                .popoverSurface(palette)
        }
    }

    /// Open while the model's picker is this side's.
    private var pickerShown: Binding<Bool> {
        Binding(
            get: { model.compare?.picker?.side == side },
            set: { if !$0, model.compare?.picker?.side == side { model.closeComparePicker() } }
        )
    }
}

/// A side's version picker: "Left side shows" with the count, a search
/// field, every version newest first with its picture and label, the one
/// chosen checked, the one on screen and the one on the other side
/// tagged, and the keys. Up and Down move, Return picks, Escape closes.
private struct ComparePickerPanel: View {
    let model: WindowModel
    let side: CompareSide
    let time: Double
    @FocusState private var isSearchFocused: Bool
    @Environment(\.palette) private var palette

    private var query: Binding<String> {
        Binding(get: { model.compare?.picker?.picker.query ?? "" }, set: { model.typeCompareQuery($0) })
    }

    var body: some View {
        let versions = model.versionSwitch
        let picker = model.compare?.picker?.picker ?? VersionPicker()
        let matches = versions?.matches(picker.query) ?? []
        let highlighted = picker.highlight(in: matches)
        let chosen = model.compare?.number(side)
        let other = model.compare?.number(side.other)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(side == .left ? "Left" : "Right") side shows")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette[.textTertiary])
                Spacer()
                Text("\(matches.count) of \(versions?.versions.count ?? 0)")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(palette[.textTertiary])
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(palette[.textTertiary])
                TextField("", text: query, prompt: Text("Find a version or label"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($isSearchFocused)
                    .onKeyPress(.upArrow) {
                        model.moveCompareHighlight(by: -1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        model.moveCompareHighlight(by: 1)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        model.pickHighlightedCompareVersion()
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        model.closeComparePicker()
                        return .handled
                    }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(palette[.well]))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette[.accent].opacity(0.7), lineWidth: 2))
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(matches) { version in
                            Button {
                                model.changeCompareForPerson(side == .left ? CompareChange(left: version.number) : CompareChange(right: version.number))
                            } label: {
                                row(version, chosen: chosen, other: other, highlighted: highlighted)
                            }
                            .buttonStyle(.plain)
                            .id(version.number)
                        }
                        if matches.isEmpty {
                            Text("No version matches “\(picker.query)”")
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette[.textTertiary])
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: min(CGFloat(max(matches.count, 2)) * 31 + 4, 8 * 31 + 4))
                .onAppear { if let chosen { scroller.scrollTo(chosen, anchor: .center) } }
                .onChange(of: highlighted) { _, number in
                    if let number { scroller.scrollTo(number) }
                }
            }
            Divider().overlay(palette[.separator])
            HStack(spacing: 8) {
                hint("↑↓", "move")
                hint("↩", "pick")
                hint("esc", "close")
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 3)
        }
        .padding(5)
        .frame(width: 320)
        .onAppear { isSearchFocused = true }
    }

    private func row(_ version: VersionSwitch.Entry, chosen: Int?, other: Int?, highlighted: Int?) -> some View {
        let isHot = version.number == highlighted
        let primary = palette[isHot ? .textOnAccent : .textPrimary]
        return HStack(spacing: 7) {
            Image(systemName: "checkmark")
                .font(.system(size: 9.5, weight: .bold))
                .opacity(version.number == chosen ? 1 : 0)
                .frame(width: 11)
            VersionStill(model: model, number: version.number, time: time, corner: 3)
                .frame(width: 38, height: 21)
            Text(version.name)
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .frame(width: 30, alignment: .leading)
            if let label = version.label {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(isHot ? palette[.textOnAccent].opacity(0.88) : palette[.textSecondary])
                    .lineLimit(1)
            } else {
                Text("no label")
                    .font(.system(size: 12).italic())
                    .foregroundStyle(isHot ? palette[.textOnAccent].opacity(0.88) : palette[.textTertiary])
            }
            Spacer(minLength: 4)
            if version.number == model.versionNumber { tag("on screen", isHot) }
            if version.number == other { tag("on \(side.other.rawValue) · swaps", isHot) }
        }
        .foregroundStyle(primary)
        .padding(.horizontal, 6)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 6).fill(isHot ? palette[.accent] : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(version.number == chosen ? .isSelected : [])
    }

    private func tag(_ text: String, _ onAccent: Bool) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(palette[onAccent ? .textOnAccent : .textTertiary])
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(Capsule().strokeBorder(onAccent ? palette[.textOnAccent].opacity(0.55) : palette[.popoverBorder]))
            .fixedSize()
    }

    private func hint(_ key: String, _ word: String) -> some View {
        HStack(spacing: 3) {
            CompareKeyCap(text: key)
            Text(word).font(.system(size: 10)).foregroundStyle(palette[.textTertiary])
        }
        .accessibilityElement(children: .combine)
    }
}
