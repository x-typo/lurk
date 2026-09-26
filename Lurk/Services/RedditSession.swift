import Foundation
import WebKit

@MainActor
@Observable
final class RedditSession {
    typealias SendLoginCheck = @MainActor (URLRequest) async throws -> (Data, URLResponse)

    enum LoginCheckResult: Equatable {
        case signedIn(name: String, modhash: String)
        case signedOut
        // Offline, timed out, or an unexpected response: nothing shows the stored sign-in is bad.
        case undetermined
    }

    private(set) var isLoggedIn = false
    private(set) var username: String?
    // Bumped when the request cookies change (sign-in, sign-out), so views holding account-specific
    // data reload. The restore at launch reuses the cookies requests already send, so it doesn't bump.
    private(set) var credentialsVersion = 0
    // Set when a check couldn't reach a verdict; the cookies stay, and the next activation checks again.
    private(set) var needsLoginCheck = false
    // The launch check, so tests can wait for it.
    private(set) var restoreTask: Task<Void, Never>?
    private var modhash: String?
    private var cookies: [HTTPCookie] = []
    private var loginCheckGeneration = 0
    private let sendLoginCheck: SendLoginCheck

    private let loginCheckURL = URL(string: "https://www.reddit.com/api/me.json")!

    // Offline, a check waits for the network instead of failing, so a launch without it restores the sign-in.
    private static let loginCheckSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    init(
        restoringSession: Bool = true,
        storedCookies: [HTTPCookie]? = nil,
        sendLoginCheck: SendLoginCheck? = nil
    ) {
        self.sendLoginCheck = sendLoginCheck ?? { try await Self.loginCheckSession.data(for: $0) }
        guard restoringSession else { return }
        // The restore reuses the cookies requests already send, so it doesn't bump credentialsVersion.
        let redditCookies = storedCookies
            ?? HTTPCookieStorage.shared.cookies?.filter { $0.domain.contains("reddit.com") }
            ?? []
        guard !redditCookies.isEmpty else { return }
        cookies = redditCookies
        restoreTask = Task { await checkLoginStatus() }
    }

    func syncCookies(from webView: WKWebView) async {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let allCookies = await store.allCookies()
        let redditCookies = allCookies.filter { $0.domain.contains("reddit.com") }

        cookies = redditCookies
        for cookie in redditCookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        credentialsVersion += 1

        await checkLoginStatus()
    }

    func checkLoginStatus() async {
        loginCheckGeneration += 1
        let generation = loginCheckGeneration
        needsLoginCheck = false
        var request = URLRequest(url: loginCheckURL)
        request.setValue(RedditAPI.userAgent, forHTTPHeaderField: "User-Agent")
        applyCookies(to: &request)

        let result: LoginCheckResult
        do {
            let (data, response) = try await sendLoginCheck(request)
            result = Self.loginCheckResult(data: data, response: response)
        } catch {
            result = .undetermined
        }
        // A newer check, a sign-in, or a sign-out has taken over.
        guard generation == loginCheckGeneration else { return }
        switch result {
        case .signedIn(let name, let hash):
            username = name
            modhash = hash
            isLoggedIn = true
        case .signedOut:
            clearSession()
        case .undetermined:
            needsLoginCheck = true
        }
    }

    // Only Reddit refusing the cookies, or answering without a user, signs out.
    nonisolated static func loginCheckResult(data: Data, response: URLResponse) -> LoginCheckResult {
        guard let http = response as? HTTPURLResponse else { return .undetermined }
        switch http.statusCode {
        case 200:
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .undetermined
            }
            guard let fields = json["data"] as? [String: Any],
                  let name = fields["name"] as? String,
                  let modhash = fields["modhash"] as? String else { return .signedOut }
            return .signedIn(name: name, modhash: modhash)
        case 401, 403:
            return .signedOut
        default:
            return .undetermined
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
            let key = Self.formEncode($0.key)
            let val = Self.formEncode($0.value)
            return "\(key)=\(val)"
        }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        applyCookies(to: &request)

        return request
    }

    private static func formEncode(_ value: String) -> String {
        var encoded = ""
        for byte in value.utf8 {
            if isFormAllowedByte(byte) {
                encoded.unicodeScalars.append(UnicodeScalar(Int(byte))!)
            } else if byte == 0x20 {
                encoded.append("+")
            } else {
                encoded += String(format: "%%%02X", byte)
            }
        }
        return encoded
    }

    private static func isFormAllowedByte(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A)
            || (byte >= 0x61 && byte <= 0x7A)
            || (byte >= 0x30 && byte <= 0x39)
            || byte == 0x2D
            || byte == 0x2E
            || byte == 0x5F
            || byte == 0x7E
    }

    func logout() async {
        // Before publishing the signed-out state, so feeds that reload for it can't send these cookies.
        HTTPCookieStorage.shared.cookies?.filter { $0.domain.contains("reddit.com") }.forEach {
            HTTPCookieStorage.shared.deleteCookie($0)
        }
        credentialsVersion += 1
        loginCheckGeneration += 1
        clearSession()
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let redditRecords = records.filter { $0.displayName.contains("reddit") }
        if !redditRecords.isEmpty {
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: redditRecords)
        }
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
        needsLoginCheck = false
    }
}
