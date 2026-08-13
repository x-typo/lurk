import SwiftUI

@main
struct LurkApp: App {
    var body: some Scene {
        WindowGroup {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-gif-simulator-fixture") {
                GIFSimulatorFixtureView()
            } else {
                LurkRootView()
            }
#else
            LurkRootView()
#endif
        }
    }
}

private struct LurkRootView: View {
    @State private var client = RedditClient()
    @State private var filterStore = PostFilterStore()
    @State private var subStore = SubredditStore()
    @State private var blockStore = BlockedSubredditStore()
    @State private var session = RedditSession()
    @State private var playbackStore = InlineGIFPlaybackStore()
    @State private var selectedTab = 0
    @State private var subredditResetKey = 0

    var body: some View {
        mainTabView
            .tint(Theme.primary)
            .preferredColorScheme(.dark)
            .environment(session)
            .environment(filterStore)
            .environment(subStore)
            .environment(blockStore)
            .environment(playbackStore)
            .environment(\.redditClient, client)
            .onChange(of: session.isLoggedIn) { _, loggedIn in
                guard loggedIn else { return }
                Task { @MainActor in
                    if let subs = try? await client.fetchSubscribedSubreddits() {
                        subStore.replaceAll(subs)
                    }
                }
            }
    }

    private var mainTabView: some View {
        TabView(selection: tabSelection) {
            PopularFeedView()
                .tabItem { Label("Popular", systemImage: "flame") }
                .tag(0)
            HomeFeedView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(1)
            SubredditsView(resetKey: subredditResetKey)
                .tabItem { Label("Subreddits", systemImage: "list.bullet") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)
        }
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab && newValue == 2 {
                    subredditResetKey += 1
                }
                selectedTab = newValue
            }
        )
    }
}
