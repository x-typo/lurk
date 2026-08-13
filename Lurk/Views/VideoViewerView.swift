import AVKit
import SwiftUI
import UIKit

struct VideoViewerView: View {
    let url: URL
    let aspectRatio: CGFloat?
    let downloadURLs: [URL]
    let loops: Bool
    @State private var player: AVPlayer
    @State private var loopObserver: NSObjectProtocol?
    @State private var dragOffset: CGSize = .zero
    @State private var dragAxis: Axis?
    @State private var saveState: SaveState = .idle
    @State private var saveTask: Task<Void, Never>?
    @State private var saveTaskID: UUID?
    @State private var shareTask: Task<Void, Never>?
    @State private var shareTaskID: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(InlineGIFPlaybackStore.self) private var playbackStore
    @State private var playbackID = UUID()

    private let dismissThreshold: CGFloat = 150

    enum SaveState {
        case idle, saving, saved, denied, failed
    }

    init(url: URL, aspectRatio: CGFloat?, downloadURLs: [URL] = [], loops: Bool = false) {
        self.url = url
        self.aspectRatio = aspectRatio
        self.downloadURLs = downloadURLs
        self.loops = loops
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
                .onAppear {
                    playbackStore.activate(playbackID)
                    configureLoopingIfNeeded()
                    player.play()
                }
                .onDisappear {
                    cancelSaveTask()
                    cancelShareTask()
                    removeLoopObserver()
                    player.pause()
                    playbackStore.deactivate(playbackID)
                }

            VStack {
                Spacer()

                HStack(spacing: 20) {
                    Spacer()

                    if !downloadURLs.isEmpty {
                        Button {
                            cancelSaveTask()
                            let operationID = UUID()
                            saveTaskID = operationID
                            saveState = .saving
                            saveTask = Task { @MainActor in
                                defer {
                                    if saveTaskID == operationID {
                                        saveTask = nil
                                        saveTaskID = nil
                                    }
                                }
                                let result = await MediaSaver.saveVideo(from: downloadURLs)
                                guard saveTaskID == operationID, !Task.isCancelled else { return }
                                switch result {
                                case .saved: saveState = .saved
                                case .denied: saveState = .denied
                                case .failed: saveState = .failed
                                }
                                do {
                                    try await Task.sleep(for: .seconds(1.5))
                                } catch {
                                    return
                                }
                                guard saveTaskID == operationID, !Task.isCancelled else { return }
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
                            cancelShareTask()
                            let operationID = UUID()
                            shareTaskID = operationID
                            shareTask = Task { @MainActor in
                                defer {
                                    if shareTaskID == operationID {
                                        shareTask = nil
                                        shareTaskID = nil
                                    }
                                }

                                do {
                                    let tempURL = try await MediaSaver.temporaryVideoFile(from: downloadURLs)
                                    var shouldCleanUp = true
                                    defer {
                                        if shouldCleanUp {
                                            try? FileManager.default.removeItem(at: tempURL)
                                        }
                                    }
                                    try Task.checkCancellation()
                                    guard shareTaskID == operationID,
                                          let presenter = topPresenter() else { return }

                                    let activityController = UIActivityViewController(
                                        activityItems: [tempURL],
                                        applicationActivities: nil
                                    )
                                    activityController.completionWithItemsHandler = { _, _, _, _ in
                                        try? FileManager.default.removeItem(at: tempURL)
                                    }
                                    activityController.popoverPresentationController?.sourceView = presenter.view
                                    activityController.popoverPresentationController?.sourceRect = CGRect(
                                        x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.midY,
                                        width: 0,
                                        height: 0
                                    )
                                    presenter.present(activityController, animated: true)
                                    shouldCleanUp = false
                                } catch {
                                    return
                                }
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: 44, height: 44)
                        }
                        .disabled(shareTask != nil)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func configureLoopingIfNeeded() {
        guard loops, loopObserver == nil, let item = player.currentItem else { return }
        let loopController = PlayerLoopController(player: player)
        loopObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor in
                loopController.restart()
            }
        }
    }

    private func removeLoopObserver() {
        guard let loopObserver else { return }
        NotificationCenter.default.removeObserver(loopObserver)
        self.loopObserver = nil
    }

    private func cancelSaveTask() {
        saveTask?.cancel()
        saveTask = nil
        saveTaskID = nil
    }

    private func cancelShareTask() {
        shareTask?.cancel()
        shareTask = nil
        shareTaskID = nil
    }

    @MainActor
    private func topPresenter() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              var presenter = scene.keyWindow?.rootViewController else {
            return nil
        }
        while let next = presenter.presentedViewController {
            presenter = next
        }
        return presenter
    }
}
