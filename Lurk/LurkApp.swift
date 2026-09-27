import SwiftUI

@main
struct LurkApp: App {
    init() {
        // From iOS 27, AsyncImage caches image data through a default session, which uses this shared cache.
        // The system default is too small to keep a feed's images. Apple documents no AsyncImage caching earlier.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
    }

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
    @Environment(\.openURL) private var openURL
    @State private var selectedTab = 0
    @State private var showsSignIn = false
    @State private var linkedThread: ThreadTarget?
    @State private var pendingLinkedThread: ThreadTarget?
    @State private var unsentText = UnsentTextTracker()

    var body: some View {
        mainTabView
            .sheet(isPresented: $showsSignIn) {
                RedditLoginView()
            }
            .sheet(item: $linkedThread) { target in
                ThreadView(target: target)
            }
            // A thread link from another app, whether Lurk was running or the link launched it.
            .onOpenURL { url in
                switch LurkLink(url) {
                case .thread(let target):
                    if unsentText.hasUnsentText {
                        pendingLinkedThread = target
                    } else {
                        linkedThread = target
                    }
                case .web(let link): openURL(link)
                case nil: break
                }
            }
            .onChange(of: unsentText.hasUnsentText) { _, hasUnsentText in
                guard !hasUnsentText, let pendingLinkedThread else { return }
                self.pendingLinkedThread = nil
                linkedThread = pendingLinkedThread
            }
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
            .environment(unsentText)
            .environment(\.redditClient, client)
            .environment(\.presentSignIn, PresentSignInAction { showsSignIn = true })
            .onChange(of: account, initial: true) { _, account in
                unreadReplies.setAccount(account)
                engagement.setAccount(account)
            }
            .task(id: account) { await refreshUnreadReplies() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await refreshUnreadReplies() }
                if session.needsLoginCheck { Task { await session.checkLoginStatus() } }
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
        TabView(selection: $selectedTab) {
            // Loaded posts carry the viewer's votes and saves, so feeds reload when the cookies change.
            NavigationStack {
                PopularFeedView()
                    .tabRootTitle("Popular")
            }
            .id(session.credentialsVersion)
            .tabItem { Label("Popular", systemImage: "flame") }
            .tag(0)
            NavigationStack {
                HomeFeedView()
                    .tabRootTitle("Home")
            }
            .id(session.credentialsVersion)
            .tabItem { Label("Home", systemImage: "house") }
            .tag(1)
            NavigationStack {
                SubredditsView()
                    .tabRootTitle("Subreddits")
            }
            .id(session.credentialsVersion)
            .tabItem { Label("Subreddits", systemImage: "list.bullet") }
            .tag(2)
            NavigationStack {
                SettingsView()
                    .tabRootTitle("Settings")
            }
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
}

private extension View {
    // A slim title bar, so content scrolls under the bar instead of under the status bar.
    func tabRootTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
