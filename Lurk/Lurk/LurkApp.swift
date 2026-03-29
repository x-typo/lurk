import SwiftUI

@main
struct LurkApp: App {
    @State private var client = RedditClient()
    @State private var filterStore = PostFilterStore()
    @State private var subStore = SubredditStore()
    @State private var selectedTab = 0
    @State private var subredditResetKey = 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                HomeFeedView(client: client, filterStore: filterStore, subStore: subStore)
                    .tabItem { Label("Home", systemImage: "house") }
                    .tag(0)
                PopularFeedView(client: client, filterStore: filterStore)
                    .tabItem { Label("Popular", systemImage: "flame") }
                    .tag(1)
                SubredditsView(client: client, filterStore: filterStore, subStore: subStore, resetKey: subredditResetKey)
                    .tabItem { Label("Subreddits", systemImage: "list.bullet") }
                    .tag(2)
            }
            .tint(Theme.primary)
            .preferredColorScheme(.dark)
            .onChange(of: selectedTab) { oldValue, newValue in
                // Double-tap Subreddits tab resets to picker
                if oldValue == 2 && newValue == 2 {
                    subredditResetKey += 1
                }
            }
        }
    }
}
