import SwiftUI

private struct RedditClientKey: EnvironmentKey {
    static let defaultValue = RedditClient()
}

extension EnvironmentValues {
    var redditClient: RedditClient {
        get { self[RedditClientKey.self] }
        set { self[RedditClientKey.self] = newValue }
    }
}
