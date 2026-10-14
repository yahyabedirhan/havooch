import ReviewCore
import ReviewWire
import SwiftUI

struct RootView: View {
    @Bindable var model: WindowModel
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
            .overlay(alignment: .top) { ConfigBanner(model: model) }
            .animation(SidebarColumn.animation(reduceMotion: reduceMotion), value: sidebarShown)
        }
        .frame(
            minWidth: Metrics.windowMinimumWidth(sidebarShown: sidebarShown),
            minHeight: Metrics.windowMinimumHeight
        )
        .tint(palette[.accent])
        .foregroundStyle(palette[.textPrimary])
        .background(palette[.window])
        .preferredColorScheme(Self.scheme(of: model.themes))
        .navigationTitle(model.video?.title ?? AppIdentity.appName)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                TitleView(words: HeaderWords(video: model.video?.url, isDemo: model.isDemo, project: model.projectWords), model: model)
            }
            .sharedBackgroundVisibility(.hidden)
            FloatingControls(model: model, lease: lease, stopLease: stopLease, isControlled: isControlled)
        }
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
        .environment(\.palette, palette)
    }

    static func scheme(of themes: ThemeDesk) -> ColorScheme? {
        guard themes.pinned != nil else { return nil }
        return themes.theme.kind == .dark ? .dark : .light
    }

    private var isControlled: Bool {
        lease.shown(at: Date()) != nil
    }

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
