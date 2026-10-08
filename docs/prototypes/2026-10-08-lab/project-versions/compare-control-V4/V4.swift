import LabHost
import SwiftUI

/// compare-control V4 "Swap and layout, live picker": V3's popover (layout
/// choice, a chip per side, the swap button) on a live 50-version project.
/// Clicking a side opens a real version picker hung under that side and
/// drawn over everything, past the popover's edge: a focused search field,
/// a newest-first list, keyboard ↑↓ ↩ esc, and "N of 50".
public let variant = LabVariant { Themed { V4Board() } }

/// Where the board measures the side chips, so the picker can hang under one.
private let boardSpace = "compare-board"

struct V4Board: View {
    @State private var left = Fixture.current - 1
    @State private var right = Fixture.current
    @State private var open: Side? = nil
    @State private var layout: CompareLayout = .sideBySide
    @State private var chipFrames: [String: CGRect] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StateCaption(text: "Compare popover · \(layout.rawValue.lowercased()) · click a side to pick its version")
            PlayerWithPopover(popoverWidth: 440, stageHeight: 372) {
                popover
            }
            StateCaption(text: "After \(layout == .sideBySide ? "Show side by side" : "Compare") · v\(left) left, v\(right) right, one playhead").padding(.top, 14)
            ComparisonWindow(left: left, right: right, layout: layout, stageHeight: 160)
        }
        .frame(width: 900)
        .padding(22)
        .coordinateSpace(.named(boardSpace))
        .overlay(alignment: .topLeading) { pickerLayer }
    }

    private var popover: some View {
        VStack(spacing: 10) {
            PopoverTitle(hint: "Pick a layout, then click a side to pick its version.")
            LayoutPicker(layout: $layout)
            MiniWindow {
                MiniPreview(layout: layout, left: left, right: right, open: open,
                            onTap: { side in open = open == side ? nil : side },
                            onSwap: { open = nil; (left, right) = (right, left) },
                            onChipFrame: { side, rect in chipFrames[side.rawValue] = rect })
            }
            PopoverFooter(action: layout == .sideBySide ? "Show side by side" : "Compare")
        }
        .padding(14)
    }

    /// The open side's picker, over the whole board, with a click-away
    /// catcher behind it.
    @ViewBuilder private var pickerLayer: some View {
        if let side = open, let chip = chipFrames[side.rawValue] {
            let width: CGFloat = 320
            let mine = side == .left ? left : right
            let theirs = side == .left ? right : left
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { open = nil }
                    .labID("picker-dismiss")
                VersionPicker(side: side, chosen: mine, other: theirs, width: width,
                              onPick: { pick($0, for: side) },
                              onCancel: { open = nil })
                    .id(side)
                    .offset(x: side == .left ? chip.minX : chip.maxX - width, y: chip.maxY + 5)
            }
        }
    }

    private func pick(_ number: Int, for side: Side) {
        let theirs = side == .left ? right : left
        if number == theirs {
            (left, right) = (right, left)
        } else if side == .left {
            left = number
        } else {
            right = number
        }
        open = nil
    }
}

// MARK: - The version picker

/// A real picker for one side: search, a newest-first list of all 50
/// versions, keyboard navigation and a count.
private struct VersionPicker: View {
    let side: Side
    let chosen: Int
    let other: Int
    var width: CGFloat = 320
    var onPick: (Int) -> Void
    var onCancel: () -> Void
    @State private var query = ""
    @State private var highlighted: Int?
    @FocusState private var searchFocused: Bool
    @Environment(\.pal) private var pal

    private var otherSide: Side { side == .left ? .right : .left }
    private var all: [Version] { Fixture.many.reversed() }

    private var shown: [Version] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        let digits = q.hasPrefix("v") ? String(q.dropFirst()) : q
        let numeric = !digits.isEmpty && digits.allSatisfy(\.isNumber)
        return all.filter { v in
            if q == "v" { return true }
            if numeric && String(v.number).hasPrefix(digits) { return true }
            return (v.label ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(side.rawValue) side shows")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(pal.textTertiary)
                Spacer()
                Text("\(shown.count) of \(all.count)")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(pal.textTertiary)
                    .labID("picker-count")
            }
            .padding(.horizontal, 6).padding(.top, 4)
            search
            list
            Divider().padding(.horizontal, 2)
            HStack(spacing: 8) {
                hint("↑↓", "move")
                hint("↩", "pick")
                hint("esc", "close")
                Spacer()
            }
            .padding(.horizontal, 6).padding(.bottom, 3)
        }
        .padding(5)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(pal.dark ? Color(white: 0.17) : Color.white))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(pal.popoverBorder))
        .shadow(color: .black.opacity(pal.dark ? 0.55 : 0.22), radius: 14, y: 6)
        .onAppear {
            highlighted = chosen
            DispatchQueue.main.async { searchFocused = true }
        }
        .onChange(of: query) { _, _ in highlighted = shown.first?.number }
        .labID("picker")
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(pal.textTertiary)
            TextField("Find a version or label", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searchFocused)
                .onSubmit { pickHighlighted() }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.escape) { onCancel(); return .handled }
                .onExitCommand { onCancel() }
                .labID("picker-search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(pal.textTertiary)
                }
                .buttonStyle(.plain)
                .labID("picker-clear")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7).fill(pal.well))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(searchFocused ? pal.accent.opacity(0.7) : pal.popoverBorder,
                                                                lineWidth: searchFocused ? 2 : 1))
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(shown) { v in
                        row(v).id(v.number)
                    }
                    if shown.isEmpty {
                        Text("No version matches “\(query)”")
                            .font(.system(size: 11.5))
                            .foregroundStyle(pal.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: min(CGFloat(max(shown.count, 2)) * 31 + 4, 8 * 31 + 4))
            .onAppear { DispatchQueue.main.async { proxy.scrollTo(chosen, anchor: .center) } }
            .onChange(of: highlighted) { _, n in
                if let n { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(n) } }
            }
        }
    }

    private func row(_ v: Version) -> some View {
        let isChosen = v.number == chosen
        let isHot = v.number == highlighted
        let onAccent = isHot
        return Button { onPick(v.number) } label: {
            HStack(spacing: 7) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .opacity(isChosen ? 1 : 0)
                    .frame(width: 11)
                VideoFrame(number: v.number, corner: 3)
                    .frame(width: 38, height: 21)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(onAccent ? 0.5 : 0), lineWidth: 1))
                Text(v.name)
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                    .frame(width: 30, alignment: .leading)
                Text(v.label ?? "no label")
                    .font(.system(size: 12))
                    .foregroundStyle(onAccent ? pal.textOnAccent.opacity(0.88)
                                     : (v.label == nil ? pal.textTertiary : pal.textSecondary))
                    .italic(v.label == nil)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if v.number == Fixture.current { tag("on screen", onAccent) }
                if v.number == other {
                    tag("on \(otherSide.rawValue.lowercased()) · swaps", onAccent)
                }
            }
            .foregroundStyle(onAccent ? pal.textOnAccent : pal.textPrimary)
            .padding(.horizontal, 6)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(onAccent ? pal.accent : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in if inside { highlighted = v.number } }
        .labID("pick-v\(v.number)")
    }

    private func tag(_ text: String, _ onAccent: Bool) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(onAccent ? pal.textOnAccent : pal.textTertiary)
            .padding(.horizontal, 5).frame(height: 16)
            .background(Capsule().strokeBorder(onAccent ? pal.textOnAccent.opacity(0.55) : pal.popoverBorder.opacity(2)))
            .fixedSize()
    }

    private func hint(_ key: String, _ word: String) -> some View {
        HStack(spacing: 3) {
            KeyCap(text: key)
            Text(word).font(.system(size: 10)).foregroundStyle(pal.textTertiary)
        }
    }

    private func move(_ step: Int) {
        let list = shown
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.number == highlighted } ?? (step > 0 ? -1 : list.count)
        highlighted = list[min(max(i + step, 0), list.count - 1)].number
    }

    private func pickHighlighted() {
        if let n = highlighted, shown.contains(where: { $0.number == n }) { onPick(n) }
        else if let first = shown.first { onPick(first.number) }
    }
}

// MARK: - Layout choice

/// Side by side · Flip · Slider, as a segmented row of icon and words.
private struct LayoutPicker: View {
    @Binding var layout: CompareLayout
    @Environment(\.pal) private var pal
    var body: some View {
        HStack(spacing: 2) {
            ForEach(CompareLayout.allCases) { l in
                let on = l == layout
                Button { layout = l } label: {
                    HStack(spacing: 5) {
                        Image(systemName: l.symbol).font(.system(size: 11))
                        Text(l.rawValue).font(.system(size: 11.5, weight: on ? .semibold : .regular))
                    }
                    .foregroundStyle(on ? pal.textPrimary : pal.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 5).fill(on ? (pal.dark ? Color.white.opacity(0.14) : Color.white) : Color.clear)
                        .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1, y: 0.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .labID("layout-\(l.id.lowercased().replacingOccurrences(of: " ", with: "-"))")
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(pal.well))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(pal.popoverBorder))
    }
}

// MARK: - The mini window's body

/// The preview frames in a layout, then one chip per side with the swap
/// button between them. Frames and chips both open their side's picker.
private struct MiniPreview: View {
    let layout: CompareLayout
    let left: Int
    let right: Int
    let open: Side?
    var onTap: (Side) -> Void = { _ in }
    var onSwap: () -> Void = {}
    var onChipFrame: (Side, CGRect) -> Void = { _, _ in }
    @Environment(\.pal) private var pal

    var body: some View {
        VStack(spacing: 6) {
            preview
                .frame(height: 84)
            HStack(spacing: 6) {
                chip(.left)
                Button(action: onSwap) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(pal.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(pal.dark ? Color.white.opacity(0.1) : Color.white))
                        .overlay(Circle().strokeBorder(pal.popoverBorder))
                }
                .buttonStyle(.plain)
                .help("Swap sides")
                .labID("swap")
                chip(.right)
            }
        }
    }

    private func number(_ side: Side) -> Int { side == .left ? left : right }
    private func name(_ side: Side) -> String {
        layout == .flip ? (side == .left ? "A" : "B") : side.rawValue.uppercased()
    }

    @ViewBuilder private var preview: some View {
        switch layout {
        case .sideBySide:
            HStack(spacing: 4) {
                frame(.left)
                frame(.right)
            }
        case .flip:
            ZStack {
                frame(.right).opacity(0.8).scaleEffect(0.84).offset(x: 16, y: -7)
                frame(.left)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.5), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .scaleEffect(0.84).offset(x: -12, y: 6)
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 3) {
                    KeyCap(text: "\\")
                    Text("flips").font(.system(size: 9.5)).foregroundStyle(pal.textSecondary)
                }
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(pal.popover))
            }
        case .slider:
            GeometryReader { geo in
                let split = geo.size.width * 0.5
                ZStack(alignment: .leading) {
                    frame(.right)
                    frame(.left).mask(alignment: .leading) { Rectangle().frame(width: split) }
                    Rectangle().fill(.white).frame(width: 1.5).offset(x: split - 0.75)
                    Circle().fill(.white).frame(width: 12, height: 12)
                        .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 6, weight: .bold)).foregroundStyle(.black.opacity(0.6)))
                        .offset(x: split - 6)
                }
            }
        }
    }

    private func frame(_ side: Side) -> some View {
        VideoFrame(number: number(side))
            .overlay(alignment: side == .left || layout == .flip ? .topLeading : .topTrailing) {
                Text("\(name(side)) · v\(number(side))")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.4)))
                    .padding(3)
            }
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(open == side ? pal.accent : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
            .onTapGesture { onTap(side) }
            .labID("pane-\(side.rawValue.lowercased())")
    }

    private func chip(_ side: Side) -> some View {
        let v = version(number(side))
        let active = open == side
        return HStack(spacing: 5) {
            Text(name(side)).font(.system(size: 8.5, weight: .bold)).tracking(0.4)
                .foregroundStyle(active ? pal.accent : pal.textTertiary)
            Text(v.name).font(.system(size: 11.5, weight: .bold).monospacedDigit())
                .foregroundStyle(active ? pal.accent : pal.textPrimary)
            Text(v.label ?? "no label").font(.system(size: 11))
                .foregroundStyle(v.label == nil ? pal.textTertiary : pal.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: active ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
                .foregroundStyle(active ? pal.accent : pal.textTertiary)
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6).fill(active ? pal.accent.opacity(0.12) : (pal.dark ? Color.white.opacity(0.06) : Color.white)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(active ? pal.accent : pal.popoverBorder, lineWidth: active ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { onTap(side) }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(boardSpace)) } action: { onChipFrame(side, $0) }
        .labID("side-\(side.rawValue.lowercased())")
    }
}
