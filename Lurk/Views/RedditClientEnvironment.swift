import SwiftUI

private struct RedditClientKey: EnvironmentKey {
    static var defaultValue: RedditClient {
        fatalError("RedditClient is not injected. Add .environment(\\.redditClient, client) at the WindowGroup root.")
    }
}

extension EnvironmentValues {
    var redditClient: RedditClient {
        get { self[RedditClientKey.self] }
        set { self[RedditClientKey.self] = newValue }
    }
}
