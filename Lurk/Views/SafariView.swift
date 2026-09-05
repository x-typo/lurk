import SafariServices
import SwiftUI

struct SafariDestination: Identifiable {
    let url: URL
    var id: URL { url }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> Presenter {
        Presenter(url: url, onFinish: onFinish)
    }

    func updateUIViewController(_ controller: Presenter, context: Context) {}

    final class Presenter: UIViewController, SFSafariViewControllerDelegate {
        let url: URL
        let onFinish: () -> Void
        private var presentedSafari = false
        private var finishedSafari = false
        private var notifiedFinish = false

        init(url: URL, onFinish: @escaping () -> Void) {
            self.url = url
            self.onFinish = onFinish
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = UIColor(Theme.background)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if finishedSafari && !notifiedFinish {
                notifiedFinish = true
                onFinish()
            } else if !presentedSafari {
                presentedSafari = true
                let safari = SFSafariViewController(url: url)
                safari.delegate = self
                safari.modalPresentationStyle = .fullScreen
                present(safari, animated: false)
            }
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            // Safari dismisses itself. Wait for this presenter to reappear before
            // closing the SwiftUI sheet, or UIKit can dismiss the post detail too.
            finishedSafari = true
        }
    }
}
