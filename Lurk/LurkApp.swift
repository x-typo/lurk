import SwiftUI

@main
struct LurkApp: App {
    @State private var client = RedditClient()
    @State private var filterStore = PostFilterStore()
    @State private var subStore = SubredditStore()
    @State private var blockStore = BlockedSubredditStore()
    @State private var session = RedditSession()
    @State private var selectedTab = 0
    @State private var subredditResetKey = 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: tabSelection) {
                PopularFeedView(client: client, filterStore: filterStore, subStore: subStore, blockStore: blockStore, session: session)
                    .tabItem { Label("Popular", systemImage: "flame") }
                    .tag(0)
                HomeFeedView(client: client, filterStore: filterStore, subStore: subStore, blockStore: blockStore, session: session)
                    .tabItem { Label("Home", systemImage: "house") }
                    .tag(1)
                SubredditsView(client: client, filterStore: filterStore, subStore: subStore, blockStore: blockStore, session: session, resetKey: subredditResetKey)
                    .tabItem { Label("Subreddits", systemImage: "list.bullet") }
                    .tag(2)
                SettingsView(session: session, client: client, filterStore: filterStore, subStore: subStore, blockStore: blockStore)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(3)
            }
            .tint(Theme.primary)
            .preferredColorScheme(.dark)
            .onChange(of: session.isLoggedIn) { _, loggedIn in
                guard loggedIn else { return }
                Task { @MainActor in
                    if let subs = try? await client.fetchSubscribedSubreddits() {
                        subStore.replaceAll(subs)
                    }
                }
            }
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
