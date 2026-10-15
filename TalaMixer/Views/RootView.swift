//
//  RootView.swift
//  TalaMixer
//
//  The app shell: a floating pill tab bar over the five main pages, in the
//  Tala Shruti style. Owns the client, reconnects when the app returns to the
//  foreground, and keeps the screen awake while live.
//

import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, mixer, effects, scenes, tools
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .mixer: return "Mixer"
        case .effects: return "Effects"
        case .scenes: return "Snapshots"
        case .tools: return "Tools"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .mixer: return "slider.vertical.3"
        case .effects: return "wand.and.sparkles"
        case .scenes: return "camera.aperture"
        case .tools: return "wrench.and.screwdriver"
        }
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var client = XAirClient()
    // "-startTab mixer" as a launch argument opens on that tab — used by tests.
    @State private var tab: AppTab =
        AppTab(rawValue: UserDefaults.standard.string(forKey: "startTab") ?? "") ?? .home
    @State private var showsConnection = false
    /// First frame matches the launch screen (logo on warm black), then fades,
    /// so launch reads as one continuous splash instead of a hard cut.
    @State private var showsLaunchCurtain = true

    @AppStorage("lastMixerHost") private var lastHost = ""
    /// Simplified mode: faders and mutes only, for whoever is covering the
    /// desk. The full surface is two taps away, not gone.
    @AppStorage("simplifiedMode") private var simplified = false

    private var visibleTabs: [AppTab] {
        simplified ? [.home, .mixer] : AppTab.allCases
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home:
                    HomeView(openTab: { tab = $0 },
                             openConnection: { showsConnection = true })
                case .mixer:
                    MixerView()
                case .effects:
                    EffectsView()
                case .scenes:
                    SnapshotsView()
                case .tools:
                    ToolsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBar(selection: $tab, tabs: visibleTabs)
                .padding(.bottom, 4)
        }
        .background(Theme.background)
        .overlay {
            if showsLaunchCurtain {
                LaunchCurtain()
                    .transition(.opacity)
            }
        }
        .onChange(of: simplified) { _, isOn in
            if isOn, !visibleTabs.contains(tab) { tab = .home }
        }
        .sheet(isPresented: $showsConnection) {
            ConnectionView()
        }
        .environment(client)
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear(perform: startup)
        .onChange(of: scenePhase) { _, phase in
            handle(phase)
        }
        .onChange(of: client.status) { _, status in
            // A mixing surface that dims mid-set is worse than a warm battery.
            setIdleTimerDisabled(status.isLive)
        }
    }

    private func startup() {
        // A breath on the logo, then a gentle fade — under a second in total,
        // never a wait the user can feel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.5)) { showsLaunchCurtain = false }
        }

        guard !lastHost.isEmpty else { return }
        if lastHost == ConnectionView.demoHost {
            client.connect(host: lastHost, demo: true)
        } else {
            client.connect(host: lastHost)
        }
    }

    private func handle(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // iOS tears down UDP sockets while suspended, so re-establish rather
            // than trusting a connection that survived backgrounding.
            if !client.status.isLive, !lastHost.isEmpty {
                startup()
            }
        case .background:
            setIdleTimerDisabled(false)
        default:
            break
        }
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

// MARK: - Launch curtain

/// A perfect copy of the system launch screen: the logo centered on the warm
/// black. It sits over the first frame and fades, purely visual.
private struct LaunchCurtain: View {
    var body: some View {
        ZStack {
            Theme.background
            Image("LaunchLogo")
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Floating tab bar

private struct TabBar: View {
    @Binding var selection: AppTab
    var tabs: [AppTab] = AppTab.allCases
    @Namespace private var pill

    /// Every tab shows icon + label at a fixed width, so targets are big and
    /// nothing shifts under the finger when the selection changes. The gold
    /// pill slides between tabs rather than teleporting.
    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                let isSelected = selection == tab
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: .medium))
                        Text(tab.title)
                            .font(Theme.label(13, weight: isSelected ? .bold : .medium))
                    }
                    .foregroundStyle(isSelected ? Color.black.opacity(0.85) : Theme.textSecondary)
                    .frame(width: 108, height: 44)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Theme.gold)
                                .shadow(color: Theme.gold.opacity(0.35), radius: 10, y: 2)
                                .matchedGeometryEffect(id: "selection", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(5)
        .background(
            Capsule()
                .fill(Theme.surface.opacity(0.94))
                .overlay(
                    Capsule().strokeBorder(Theme.cardEdge, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main navigation")
    }
}

#Preview {
    RootView()
}
