import SwiftUI

@main
struct LurkApp: App {
    var body: some Scene {
        WindowGroup {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-inbox-simulator-fixture"),
               Bundle.main.bundleIdentifier == "com.xtypo.Lurk.inboxQA" {
                InboxSimulatorFixtureView()
            } else if ProcessInfo.processInfo.arguments.contains("-gif-simulator-fixture") {
                GIFSimulatorFixtureView()
            } else if ProcessInfo.processInfo.arguments.contains("-reading-simulator-fixture"),
                      Bundle.main.bundleIdentifier == "com.xtypo.Lurk.readingQA" {
                ReadingSimulatorFixtureView()
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
    @State private var muteStore = MuteStore()
    @State private var hideSync = PostHideSync()
    @State private var engagement = EngagementStore()
    @State private var session = RedditSession()
    @State private var playbackStore = InlineGIFPlaybackStore()
    @State private var unreadReplies = UnreadRepliesStore()
    @Environment(\.scenePhase) private var scenePhase
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
            .environment(muteStore)
            .environment(hideSync)
            .environment(engagement)
            .environment(playbackStore)
            .environment(unreadReplies)
            .environment(\.redditClient, client)
            .onChange(of: account, initial: true) { _, account in
                unreadReplies.setAccount(account)
                engagement.setAccount(account)
            }
            .task(id: account) { await refreshUnreadReplies() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refreshUnreadReplies() } }
            }
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
            // Loaded posts carry the viewer's votes and saves, so feeds reload when the cookies change.
            PopularFeedView()
                .id(session.credentialsVersion)
                .tabItem { Label("Popular", systemImage: "flame") }
                .tag(0)
            HomeFeedView()
                .id(session.credentialsVersion)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(1)
            SubredditsView(resetKey: subredditResetKey)
                .id(session.credentialsVersion)
                .tabItem { Label("Subreddits", systemImage: "list.bullet") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .modifier(UnreadRepliesTabBadge())
                .tag(3)
        }
    }

    private var account: String? { session.isLoggedIn ? session.username : nil }

    private func refreshUnreadReplies() async {
        let currentAccount = account
        await unreadReplies.refresh(account: currentAccount) { filter, after in
            guard let currentAccount, account == currentAccount else {
                throw URLError(.userAuthenticationRequired)
            }
            return try await client.fetchInboxReplies(filter: filter, after: after)
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
