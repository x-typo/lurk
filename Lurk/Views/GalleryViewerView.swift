import SwiftUI
import UIKit

struct ExternalMediaURLOpener {
    let handler: (URL) -> Void

    @discardableResult
    func open(_ url: URL) -> Bool {
        guard url.isHTTPMediaURL else { return false }
        handler(url)
        return true
    }

    static let system = ExternalMediaURLOpener { url in
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

struct GalleryViewerView: View {
    let items: [GalleryMedia]
    private let externalURLOpener: ExternalMediaURLOpener
    @State private var currentPage = 0
    @State private var currentPageLoadState: ZoomableImageView.LoadState = .loading
    @State private var dragOffset: CGSize = .zero
    @State private var dragAxis: Axis?
    @State private var saveState: SaveState = .idle
    @State private var saveTask: Task<Void, Never>?
    @State private var saveTaskID: UUID?
    @State private var shareTask: Task<Void, Never>?
    @State private var shareTaskID: UUID?
    @State private var playbackID = UUID()
    @Environment(InlineGIFPlaybackStore.self) private var playbackStore
    @Environment(\.dismiss) private var dismiss

    private let dismissThreshold: CGFloat = 150

    enum SaveState {
        case idle, saving, saved, failed
    }

    init(
        items: [GalleryMedia],
        externalURLOpener: ExternalMediaURLOpener = .system
    ) {
        self.items = items
        self.externalURLOpener = externalURLOpener
    }

    private var currentItem: GalleryMedia? {
        guard currentPage >= 0, currentPage < items.count else { return nil }
        return items[currentPage]
    }

    var body: some View {
        let dragProgress: CGFloat = min(abs(dragOffset.height) / dismissThreshold, 1.0)

        ZStack(alignment: .topTrailing) {
            Theme.background.ignoresSafeArea()
                .opacity(Double(1 - dragProgress * 0.5))

            TabView(selection: $currentPage) {
                ForEach(items) { item in
                    ZoomableImageView(
                        url: item.url,
                        isAnimated: item.isAnimated,
                        isActive: item.id == currentPage,
                        posterURL: item.posterURL,
                        onLoadStateChange: { state in
                            guard item.id == currentPage else { return }
                            currentPageLoadState = state
                        }
                    )
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
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
                            dismiss()
                        } else {
                            withAnimation(.spring()) { dragOffset = .zero }
                        }
                    }
            )

            if currentPageLoadState == .tooLarge, let item = currentItem {
                oversizedGIFFallback(for: item)
                    .zIndex(1)
            }

            VStack {
                Spacer()

                HStack(spacing: 20) {
                    Spacer()

                    Text("\(currentPage + 1) / \(items.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5))
                        .clipShape(Capsule())

                    Spacer()

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
                            guard saveTaskID == operationID, !Task.isCancelled else { return }
                            guard let item = currentItem else {
                                saveState = .failed
                                do {
                                    try await Task.sleep(for: .seconds(1.5))
                                } catch {
                                    return
                                }
                                guard saveTaskID == operationID, !Task.isCancelled else { return }
                                saveState = .idle
                                return
                            }
                            let result = item.isAnimated
                                ? await MediaSaver.saveImageData(from: item.url)
                                : await MediaSaver.saveImage(from: item.url)
                            guard saveTaskID == operationID, !Task.isCancelled else { return }
                            saveState = result == .saved ? .saved : .failed
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
                            guard let item = currentItem else { return }

                            if item.isAnimated {
                                do {
                                    let temporaryGIFURL = try await MediaSaver.temporaryGIFFile(from: item.url)
                                    var shouldCleanUp = true
                                    defer {
                                        if shouldCleanUp {
                                            try? FileManager.default.removeItem(at: temporaryGIFURL)
                                        }
                                    }
                                    try Task.checkCancellation()

                                    let activityController = UIActivityViewController(
                                        activityItems: [temporaryGIFURL],
                                        applicationActivities: nil
                                    )
                                    activityController.completionWithItemsHandler = { _, _, _, _ in
                                        try? FileManager.default.removeItem(at: temporaryGIFURL)
                                    }
                                    guard let presenter = topPresenter() else { return }
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
                            } else {
                                guard let (data, _) = try? await URLSession.shared.data(from: item.url),
                                      let image = UIImage(data: data) else { return }
                                presentShareSheet(for: image)
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
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: currentPage) { _, _ in
            cancelSaveTask()
            cancelShareTask()
            saveState = .idle
            currentPageLoadState = .loading
        }
        .onAppear {
            playbackStore.activate(playbackID)
        }
        .onDisappear {
            cancelSaveTask()
            cancelShareTask()
            playbackStore.deactivate(playbackID)
        }
    }

    private func oversizedGIFFallback(for item: GalleryMedia) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Theme.textMuted)
            Text("GIF is too large to animate safely")
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
            Button {
                externalURLOpener.open(item.url)
            } label: {
                Label("Open in Browser", systemImage: "arrow.up.right.square")
                    .font(.callout.weight(.semibold))
                    .frame(minHeight: 44)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .contentShape(Rectangle())
            .accessibilityHint("Opens the GIF in your default browser")
        }
        .padding(16)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    private func presentShareSheet(for item: Any) {
        guard let presenter = topPresenter() else { return }
        let activityController = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        activityController.popoverPresentationController?.sourceView = presenter.view
        activityController.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX,
            y: presenter.view.bounds.midY,
            width: 0,
            height: 0
        )
        presenter.present(activityController, animated: true)
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
