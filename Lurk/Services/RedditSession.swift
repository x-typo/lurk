import Foundation
import WebKit

@MainActor
@Observable
final class RedditSession {
    private(set) var isLoggedIn = false
    private(set) var username: String?
    private var modhash: String?
    private var cookies: [HTTPCookie] = []

    private let loginCheckURL = URL(string: "https://www.reddit.com/api/me.json")!

    init() {
        restoreSession()
    }

    func syncCookies(from webView: WKWebView) async {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let allCookies = await store.allCookies()
        let redditCookies = allCookies.filter { $0.domain.contains("reddit.com") }

        cookies = redditCookies
        for cookie in redditCookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }

        await checkLoginStatus()
    }

    func checkLoginStatus() async {
        var request = URLRequest(url: loginCheckURL)
        request.setValue(RedditAPI.userAgent, forHTTPHeaderField: "User-Agent")
        applyCookies(to: &request)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                clearSession()
                return
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let data = json?["data"] as? [String: Any],
               let name = data["name"] as? String,
               let mh = data["modhash"] as? String {
                username = name
                modhash = mh
                isLoggedIn = true
            } else {
                clearSession()
            }
        } catch {
            clearSession()
        }
    }

    func authenticatedRequest(url: URL, formData: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(RedditAPI.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var params = formData
        if let mh = modhash {
            params["uh"] = mh
        }

        let body = params.map {
            let key = $0.key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.key
            let val = $0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value
            return "\(key)=\(val)"
        }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        applyCookies(to: &request)

        return request
    }

    func logout() async {
        clearSession()
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let redditRecords = records.filter { $0.displayName.contains("reddit") }
        if !redditRecords.isEmpty {
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: redditRecords)
        }
        HTTPCookieStorage.shared.cookies?.filter { $0.domain.contains("reddit.com") }.forEach {
            HTTPCookieStorage.shared.deleteCookie($0)
        }
    }

    private func restoreSession() {
        let redditCookies = HTTPCookieStorage.shared.cookies?.filter { $0.domain.contains("reddit.com") } ?? []
        guard !redditCookies.isEmpty else { return }
        cookies = redditCookies
        Task { await checkLoginStatus() }
    }

    private func applyCookies(to request: inout URLRequest) {
        let headers = HTTPCookie.requestHeaderFields(with: cookies)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    private func clearSession() {
        isLoggedIn = false
        username = nil
        modhash = nil
        cookies = []
    }
}
