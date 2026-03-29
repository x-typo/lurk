import Foundation

@Observable
final class PostFilterStore {
    private static let storageKey = "lurk.hiddenPostIDs"
    private static let maxEntries = 5000

    private(set) var hiddenIDs: Set<String> = []

    init() {
        load()
    }

    func hidePost(_ id: String, remoteSync: (() async throws -> Void)? = nil) {
        hiddenIDs.insert(id)
        persist()
        if let sync = remoteSync {
            Task {
                try? await sync()
            }
        }
    }

    func isHidden(_ id: String) -> Bool {
        hiddenIDs.contains(id)
    }

    func clearAll() {
        hiddenIDs.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    private func load() {
        if let stored = UserDefaults.standard.array(forKey: Self.storageKey) as? [String] {
            hiddenIDs = Set(stored.suffix(Self.maxEntries))
        }
    }

    private func persist() {
        let arr = Array(hiddenIDs).suffix(Self.maxEntries)
        UserDefaults.standard.set(Array(arr), forKey: Self.storageKey)
    }
}
