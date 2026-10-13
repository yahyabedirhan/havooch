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
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Group {
                    switch StageContent(model) {
                    case .player:
                        VStack(spacing: 0) {
                            StageView(model: model)
                                // The setup tour's panel over the foot of the stage.
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
                        // The sound panel over the foot of the stage, pointing
                        // at the bar's speaker: inside the views that take its clicks.
                        .overlay(alignment: .topLeading) { SoundPanel(model: model) }
                        .coordinateSpace(.named(SoundPanel.space))
                    case .home:
                        HomeScreen(model: model)
                    case .empty:
                        EmptyState(model: model)
                    }
                }
                .frame(minWidth: Metrics.stageMinimumWidth, maxWidth: .infinity)
                if sidebarShown {
                    SidebarColumn(
                        model: model,
                        preferredWidth: Metrics.sidebarWidth(preferred: model.sidebarWidth, windowWidth: geometry.size.width),
                        maximumWidth: Metrics.sidebarMaximumWidth(windowWidth: geometry.size.width)
                    )
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                }
            }
            // The settings notice over the stage and the home screen alike.
            .overlay(alignment: .top) { ConfigBanner(model: model) }
            // One motion, a spring with no bounce, whatever opens or closes the
            // sidebar: the toggle, a notice, or the operator.
            .animation(SidebarColumn.animation(reduceMotion: reduceMotion), value: sidebarShown)
        }
        .frame(
            minWidth: Metrics.windowMinimumWidth(sidebarShown: sidebarShown),
            minHeight: Metrics.windowMinimumHeight
        )
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
