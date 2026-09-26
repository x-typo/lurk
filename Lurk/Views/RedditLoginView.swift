import SwiftUI
import WebKit

struct RedditLoginView: View {
    @Environment(RedditSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RedditWebView(session: session, onLogin: { dismiss() })
                .navigationTitle("Sign in to Reddit")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(Theme.primary)
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}

// Presents the sign-in sheet from LurkRootView, above the feeds. Signing in bumps the session's
// credentials version, which rebuilds the feeds before the login check finishes, so a sheet a feed
// presented would close even when the sign-in then failed.
struct PresentSignInAction {
    let action: () -> Void

    func callAsFunction() { action() }
}

private struct PresentSignInKey: EnvironmentKey {
    static let defaultValue = PresentSignInAction {}
}

extension EnvironmentValues {
    var presentSignIn: PresentSignInAction {
        get { self[PresentSignInKey.self] }
        set { self[PresentSignInKey.self] = newValue }
    }
}

struct RedditWebView: UIViewRepresentable {
    let session: RedditSession
    let onLogin: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, onLogin: onLogin)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // Reddit's login page can route to the home page without a navigation (seen when the web view is
        // already signed in), and no delegate callback reports that, so URL changes are checked too.
        context.coordinator.urlObservation = webView.observe(\.url) { [weak coordinator = context.coordinator] webView, _ in
            coordinator?.checkForLogin(in: webView)
        }
        webView.isOpaque = false
        webView.backgroundColor = UIColor(Theme.background)
        webView.scrollView.backgroundColor = UIColor(Theme.background)
        let url = URL(string: "https://www.reddit.com/login/")!
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let session: RedditSession
        let onLogin: () -> Void
        var urlObservation: NSKeyValueObservation?
        private var hasCheckedLogin = false

        init(session: RedditSession, onLogin: @escaping () -> Void) {
            self.session = session
            self.onLogin = onLogin
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkForLogin(in: webView)
        }

        func checkForLogin(in webView: WKWebView) {
            guard let url = webView.url else { return }
            let path = url.path

            let isPostLogin = path == "/" || path.isEmpty || path.hasPrefix("/r/")
                || path.hasPrefix("/user/") || url.absoluteString == "https://www.reddit.com/"

            if isPostLogin && !hasCheckedLogin {
                hasCheckedLogin = true
                Task {
                    await session.syncCookies(from: webView)
                    if session.isLoggedIn {
                        await MainActor.run { onLogin() }
                    } else {
                        hasCheckedLogin = false
                    }
                }
            }
        }
    }
}
