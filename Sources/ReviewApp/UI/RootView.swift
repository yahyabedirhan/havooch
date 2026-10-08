import ReviewCore
import ReviewWire
import SwiftUI

/// The window: the header at the top, the stage with the player bar under
/// it, and the sidebar at the side with its footer under it. With no
/// video, the home screen with the recent videos, or with none a place to
/// open one. All of it is on one surface, the theme's
/// `window`; hairlines, not background colours, separate the parts.
struct RootView: View {
    @Bindable var model: WindowModel
    /// The lease as the header's agent-control icon draws it, and its Stop.
    let lease: AgentControlIcon
    let stopLease: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = Palette(theme: model.themes.theme)
        HStack(spacing: 0) {
            Group {
                switch StageContent(model) {
                case .player:
                    VStack(spacing: 0) {
                        StageView(model: model)
                            // The setup tour's panel over the foot of the stage (H4).
                            .overlay(alignment: .bottomLeading) {
                                if model.tour.isOpen {
                                    TourPanel(model: model)
                                        .padding(.leading, 24)
                                        .padding(.bottom, 12)
                                        .transition(
                                            reduceMotion
                                                ? .opacity
                                                : .scale(scale: 0.96, anchor: .bottomLeading).combined(with: .opacity)
                                        )
                                }
                            }
                            .animation(
                                reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.86),
                                value: model.tour.isOpen
                            )
                        PlayerBar(model: model)
                    }
                case .home:
                    HomeScreen(model: model)
                case .empty:
                    EmptyState(model: model)
                }
            }
            .frame(minWidth: 480, maxWidth: .infinity)
            if sidebarShown {
                SidebarColumn(model: model)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing))
            }
        }
        // The settings notice over the stage and the home screen alike.
        .overlay(alignment: .top) { ConfigBanner(model: model) }
        // One motion, a spring with no bounce, whatever opens or closes the
        // sidebar: the toggle, a notice, or the operator.
        .animation(SidebarColumn.animation(reduceMotion: reduceMotion), value: sidebarShown)
        .frame(minWidth: 760, minHeight: 480)
        // The theme's accent in place of the system's, for a selection and
        // a prominent button.
        .tint(palette[.accent])
        .foregroundStyle(palette[.textPrimary])
        .background(palette[.window])
        // A pinned theme's kind is the window's appearance, so the title
        // bar, the toolbar and the system's controls match it when it
        // differs from the system's. With no pin the window follows the
        // app's appearance, which the theme follows already. SwiftUI sets
        // the window's appearance on each update from this preference: an
        // AppKit view that set it as well fought SwiftUI in a loop.
        .preferredColorScheme(Self.scheme(of: model.themes))
        // The window's title stays for the Window menu and VoiceOver; the
        // header draws its own, with icons.
        .navigationTitle(model.video?.title ?? AppIdentity.appName)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                TitleView(words: HeaderWords(video: model.video?.url, isDemo: model.isDemo, project: model.projectWords), model: model)
            }
            .sharedBackgroundVisibility(.hidden)
            FloatingControls(model: model, lease: lease, stopLease: stopLease, isControlled: isControlled)
        }
        // A painted theme paints the toolbar band in `window`; a native
        // one leaves it to the system, so the macOS toolbar shows.
        .toolbarBackground(palette[.window], for: .windowToolbar)
        .toolbarBackgroundVisibility(palette.isNative ? .automatic : .visible, for: .windowToolbar)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.openForPerson(url)
            return true
        }
        .alert(model.problem?.title ?? "", isPresented: hasProblem) {
            Button("OK") {}
        } message: {
            Text(model.problem?.reason ?? "")
        }
        // Last, so the toolbar and every popover read it too.
        .environment(\.palette, palette)
    }

    /// A window's colour scheme: a pinned theme's kind, else the app's.
    /// Settings takes it too.
    static func scheme(of themes: ThemeDesk) -> ColorScheme? {
        guard themes.pinned != nil else { return nil }
        return themes.theme.kind == .dark ? .dark : .light
    }

    /// Whether the agent-control icon is in the header: while an agent
    /// holds the lease, unless a screenshot leaves the icon out.
    private var isControlled: Bool {
        lease.shown(at: Date()) != nil
    }

    /// The sidebar shows beside a video only: never on the home screen or
    /// the empty state.
    private var sidebarShown: Bool {
        StageContent(model).showsSidebar && model.isSidebarVisible
    }

    private var hasProblem: Binding<Bool> {
        Binding(
            get: { model.problem != nil },
            set: { if !$0 { model.problem = nil } }
        )
    }
}

/// The sidebar column: the threads, the composer and the footer, resizable from its
/// leading edge between `Metrics.sidebarWidthRange`'s bounds. A hairline
/// on that edge separates it from the stage.
struct SidebarColumn: View {
    let model: WindowModel
    /// The width while the person drags; nil shows the kept width.
    @State private var dragged: CGFloat?
    /// The width when the drag started.
    @State private var dragStart: CGFloat?
    @Environment(\.palette) private var palette

    /// The column's motion: a critically damped spring, so it
    /// settles without a bounce; a short fade when motion is reduced.
    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            SidebarView(model: model)
                .frame(maxHeight: .infinity)
            // One composer for the list and the thread view alike (L41);
            // the Connect view writes nothing.
            if model.connect == nil {
                Composer(model: model)
            }
            SidebarFooter(model: model)
        }
        .frame(width: width)
        .background(palette[.window])
        .overlay(alignment: .leading) { Hairline(axis: .vertical) }
        .overlay(alignment: .leading) { resizeHandle }
    }

    private var width: CGFloat { dragged ?? model.sidebarWidth }

    /// A thin strip on the leading edge that drags the width. The width is
    /// kept in the settings when the drag ends (D 5.10).
    private var resizeHandle: some View {
        Color.clear
            .frame(width: 6)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = dragStart ?? width
                        dragStart = start
                        let range = Metrics.sidebarWidthRange
                        dragged = min(max(start - drag.translation.width, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        if let dragged { model.keepSidebarWidth(dragged) }
                        dragStart = nil
                        dragged = nil
                    }
            )
            .accessibilityHidden(true)
    }
}

/// A hairline in the theme's `separator`, one pixel thick on the screen it
/// shows on. It separates two parts of the window's one surface.
struct Hairline: View {
    let axis: Axis
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let thickness = 1 / max(displayScale, 1)
        Rectangle()
            .fill(palette[.separator])
            .frame(width: axis == .vertical ? thickness : nil, height: axis == .horizontal ? thickness : nil)
            .accessibilityHidden(true)
    }
}
