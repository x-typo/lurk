import Foundation

@MainActor
@Observable
final class UnreadRepliesStore {
    private(set) var hasUnread = false
    private(set) var account: String?
    private(set) var accountGeneration = 0
    var snapshotContext: Int { generation }

    private var generation = 0
    private var unreadIDs: Set<String> = []
    private var isComplete = false

    func setAccount(_ account: String?) {
        guard self.account != account else { return }
        self.account = account
        accountGeneration += 1
        generation += 1
        hasUnread = false
        unreadIDs = []
        isComplete = false
    }

    func refresh(account: String?, fetchPage: InboxStore.FetchPage) async {
        setAccount(account)
        guard let account, !Task.isCancelled else { return }
        generation += 1
        let requestGeneration = generation
        let scan = InboxStore()
        await scan.load(filter: .unread, account: account, fetchPage: fetchPage)
        guard requestGeneration == generation, !Task.isCancelled,
              scan.hasLoaded, scan.error == nil else { return }
        applySnapshot(scan)
    }

    func reconcile(_ inbox: InboxStore, account: String?, context: Int) {
        guard account != nil, self.account == account, snapshotContext == context,
              !Task.isCancelled, inbox.hasLoaded, !inbox.isLoading, !inbox.isLoadingMore,
              inbox.error == nil, inbox.paginationError == nil else { return }
        generation += 1
        applySnapshot(inbox)
    }

    private func applySnapshot(_ scan: InboxStore) {
        let ids = Set(scan.replies.filter(\.isUnread).map(\.id))
        if !ids.isEmpty || scan.after == nil {
            unreadIDs = ids
            isComplete = scan.after == nil
            hasUnread = !ids.isEmpty
        } else {
            isComplete = false
        }
        // A bounded scan with continuation cannot establish that the inbox is empty.
    }

    func didMarkRead(_ id: String, account: String?, accountGeneration: Int) {
        guard account != nil, self.account == account,
              self.accountGeneration == accountGeneration else { return }
        generation += 1
        unreadIDs.remove(id)
        if isComplete { hasUnread = !unreadIDs.isEmpty }
    }
}
