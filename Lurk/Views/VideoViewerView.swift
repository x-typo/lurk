import AVKit
import SwiftUI
import UIKit

struct VideoViewerView: View {
    let url: URL
    let aspectRatio: CGFloat?
    let downloadURLs: [URL]
    @State private var player: AVPlayer
    @State private var dragOffset: CGSize = .zero
    @State private var dragAxis: Axis?
    @State private var saveState: SaveState = .idle
    @Environment(\.dismiss) private var dismiss

    private let dismissThreshold: CGFloat = 150

    enum SaveState {
        case idle, saving, saved, denied, failed
    }

    init(url: URL, aspectRatio: CGFloat?, downloadURLs: [URL] = []) {
        self.url = url
        self.aspectRatio = aspectRatio
        self.downloadURLs = downloadURLs
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        let dragProgress: CGFloat = min(abs(dragOffset.height) / dismissThreshold, 1.0)

        ZStack {
            Theme.background.ignoresSafeArea()
                .opacity(Double(1 - dragProgress * 0.5))

            AVKitPlayerView(player: player)
                .aspectRatio(aspectRatio ?? 16/9, contentMode: .fit)
                .offset(y: dragOffset.height)
                .scaleEffect(CGFloat(1 - dragProgress * 0.15))
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            if dragAxis == nil {
                                dragAxis = abs(value.translation.height) > abs(value.translation.width) ? .vertical : .horizontal
                            }
                            guard dragAxis == .vertical else { return }
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            defer { dragAxis = nil }
                            guard dragAxis == .vertical else { return }
                            if abs(value.translation.height) > dismissThreshold {
                                player.pause()
                                dismiss()
                            } else {
                                withAnimation(.spring()) { dragOffset = .zero }
                            }
                        }
                )
                .onAppear { player.play() }
                .onDisappear { player.pause() }

            VStack {
                Spacer()

                HStack(spacing: 20) {
                    Spacer()

                    if !downloadURLs.isEmpty {
                        Button {
                            saveState = .saving
                            Task {
                                let result = await MediaSaver.saveVideo(from: downloadURLs)
                                switch result {
                                case .saved: saveState = .saved
                                case .denied: saveState = .denied
                                case .failed: saveState = .failed
                                }
                                try? await Task.sleep(for: .seconds(1.5))
                                saveState = .idle
                            }
                        } label: {
                            Group {
                                switch saveState {
                                case .idle:
                                    Image(systemName: "square.and.arrow.down")
                                case .saving:
                                    ProgressView().tint(.white)
                                case .saved:
                                    Image(systemName: "checkmark")
                                case .denied:
                                    Image(systemName: "lock.slash")
                                case .failed:
                                    Image(systemName: "xmark")
                                }
                            }
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 44, height: 44)
                        }
                        .disabled(saveState != .idle)

                        Button {
                            Task {
                                guard let tempURL = try? await MediaSaver.temporaryVideoFile(from: downloadURLs) else { return }
                                let ac = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                                ac.completionWithItemsHandler = { _, _, _, _ in
                                    try? FileManager.default.removeItem(at: tempURL)
                                }
                                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                      var presenter = scene.keyWindow?.rootViewController else {
                                    try? FileManager.default.removeItem(at: tempURL)
                                    return
                                }
                                while let next = presenter.presentedViewController {
                                    presenter = next
                                }
                                ac.popoverPresentationController?.sourceView = presenter.view
                                ac.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                                presenter.present(ac, animated: true)
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: 44, height: 44)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
    }
}
