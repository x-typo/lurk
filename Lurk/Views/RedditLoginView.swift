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
        private var hasCheckedLogin = false

        init(session: RedditSession, onLogin: @escaping () -> Void) {
            self.session = session
            self.onLogin = onLogin
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
