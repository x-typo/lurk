import SwiftUI

@main
struct LurkApp: App {
    @State private var client = RedditClient()
    @State private var filterStore = PostFilterStore()
    @State private var subStore = SubredditStore()
    @State private var session = RedditSession()
    @State private var selectedTab = 0
    @State private var subredditResetKey = 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: tabSelection) {
                PopularFeedView(client: client, filterStore: filterStore, session: session)
                    .tabItem { Label("Popular", systemImage: "flame") }
                    .tag(0)
                HomeFeedView(client: client, filterStore: filterStore, subStore: subStore, session: session)
                    .tabItem { Label("Home", systemImage: "house") }
                    .tag(1)
                SubredditsView(client: client, filterStore: filterStore, subStore: subStore, session: session, resetKey: subredditResetKey)
                    .tabItem { Label("Subreddits", systemImage: "list.bullet") }
                    .tag(2)
                SettingsView(session: session)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(3)
            }
            .tint(Theme.primary)
            .preferredColorScheme(.dark)
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
