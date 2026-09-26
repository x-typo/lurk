import Foundation
import Testing
@testable import Lurk

@MainActor
@Suite("Mute store")
struct MuteStoreTests {
    @Test("A fresh install mutes the old hard-coded bots and no keywords")
    func seedsOnFirstRun() {
        withDefaults { defaults in
            let store = MuteStore(defaults: defaults)
            #expect(store.users.count == 10)
            #expect(store.isMuted(user: "AutoModerator"))
            #expect(store.isMuted(user: "pcmrbot"))
            #expect(store.isMuted(user: "TrendingTattler"))
            #expect(store.keywords.isEmpty)
            #expect(!store.matchesKeyword(in: "Artemis II crew returns"))
        }
    }

    @Test("Mutes persist, and a removed seed stays removed")
    func persists() {
        withDefaults { defaults in
            let store = MuteStore(defaults: defaults)
            store.unmuteUser("automoderator")
            store.muteUser("u/SomeUser")
            store.muteKeyword("  spoilers  ")

            let reloaded = MuteStore(defaults: defaults)
            #expect(!reloaded.isMuted(user: "AutoModerator"))
            #expect(reloaded.isMuted(user: "someuser"))
            #expect(reloaded.users.count == 10)
            #expect(reloaded.keywords == ["spoilers"])
        }
    }

    @Test("Usernames are normalized, deduplicated ignoring case, and validated")
    func normalizesUsers() {
        withDefaults { defaults in
            let store = MuteStore(defaults: defaults)
            #expect(store.muteUser("/u/Some_User-1") == "Some_User-1")
            #expect(store.muteUser("@some_user-1") == "some_user-1")
            #expect(store.muteUser(" U/another ") == "another")
            #expect(store.users.filter { $0.lowercased() == "some_user-1" }.count == 1)
            for invalid in ["", "   ", "two words", "bad/name", "u/", "name!", String(repeating: "a", count: 33)] {
                #expect(store.muteUser(invalid) == nil, "Accepted \(invalid)")
            }
        }
    }

    @Test("Keywords match whole words and phrases, ignoring case")
    func matchesWholeWords() {
        withDefaults { defaults in
            let store = MuteStore(defaults: defaults)
            store.muteKeyword("AI")
            store.muteKeyword("open   source")
            store.muteKeyword("C++")
            store.muteKeyword("(beta)")

            #expect(store.matchesKeyword(in: "New AI model released"))
            #expect(store.matchesKeyword(in: "The ai's answer"))
            #expect(store.matchesKeyword(in: "AI_art contest"))
            #expect(store.matchesKeyword(in: "Why OPEN SOURCE wins"))
            #expect(store.matchesKeyword(in: "Learning C++ in 2026"))
            #expect(store.matchesKeyword(in: "App (beta) is out"))
            #expect(!store.matchesKeyword(in: "She said it rained"))
            #expect(!store.matchesKeyword(in: "Open sourcery"))
            #expect(!store.matchesKeyword(in: "C+ grade"))
            #expect(!store.matchesKeyword(in: "beta release"))
        }
    }

    @Test("Keywords are trimmed, deduplicated, validated, and removable")
    func managesKeywords() {
        withDefaults { defaults in
            let store = MuteStore(defaults: defaults)
            #expect(store.muteKeyword("Spoilers") == "Spoilers")
            #expect(store.muteKeyword("spoilers") == "spoilers")
            #expect(store.keywords == ["Spoilers"])
            for invalid in ["", "   ", "!!!", String(repeating: "a", count: 61)] {
                #expect(store.muteKeyword(invalid) == nil, "Accepted \(invalid)")
            }
            store.unmuteKeyword("SPOILERS")
            #expect(store.keywords.isEmpty)
            #expect(!store.matchesKeyword(in: "Spoilers ahead"))
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "MuteStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }
}
