import SwiftUI
import UIKit

fileprivate enum AnimatedGIFSource: Equatable {
    case remote(URL)
#if DEBUG
    case data(Data)
#endif

    var remoteURL: URL? {
        guard case .remote(let url) = self else { return nil }
        return url
    }
}

struct MediaActionAccessibility {
    let label: String
    let hint: String

    static let openGIF = Self(
        label: "Open GIF",
        hint: "Double-tap to open this GIF."
    )
}

@Observable
@MainActor
final class InlineGIFPlaybackStore {
    private struct Candidate: Equatable {
        let frame: CGRect
        let viewport: CGRect
        let isEligible: Bool

        var visibleFraction: CGFloat {
            let intersection = frame.intersection(viewport)
            guard !intersection.isNull,
                  intersection.width > 1,
                  intersection.height > 1 else { return 0 }

            let frameArea = frame.width * frame.height
            let viewportArea = viewport.width * viewport.height
            let referenceArea = min(frameArea, viewportArea)
            guard referenceArea > 0 else { return 0 }

            let visibleArea = intersection.width * intersection.height
            return visibleArea / referenceArea
        }
    }

    private(set) var activeIDs: Set<UUID> = []
    private var explicitID: UUID?
    private var candidates: [UUID: Candidate] = [:]
    private var ineligibleCandidateIDs: Set<UUID> = []

    func isActive(_ id: UUID) -> Bool {
        activeIDs.contains(id)
    }

    func activate(_ id: UUID) {
        explicitID = id
        selectCandidates()
    }

    func deactivate(_ id: UUID) {
        guard explicitID == id else { return }
        explicitID = nil
        selectCandidates()
    }

    func suspend() -> InlineGIFPlaybackSuspension {
        InlineGIFPlaybackSuspension(store: self)
    }

    func updateCandidate(_ id: UUID, frame: CGRect) {
        guard let viewport = Self.activeViewport else { return }
        updateCandidate(id, frame: frame, viewport: viewport)
    }

    func updateCandidate(_ id: UUID, frame: CGRect, viewport: CGRect) {
        candidates[id] = Candidate(
            frame: frame,
            viewport: viewport,
            isEligible: !ineligibleCandidateIDs.contains(id)
        )
        selectCandidates()
    }

    func setCandidateEligible(_ isEligible: Bool, id: UUID) {
        if isEligible {
            ineligibleCandidateIDs.remove(id)
        } else {
            ineligibleCandidateIDs.insert(id)
        }
        if let candidate = candidates[id] {
            candidates[id] = Candidate(
                frame: candidate.frame,
                viewport: candidate.viewport,
                isEligible: isEligible
            )
        }
        selectCandidates()
    }

    func removeCandidate(_ id: UUID) {
        candidates.removeValue(forKey: id)
        ineligibleCandidateIDs.remove(id)
        selectCandidates()
    }

    private func selectCandidates() {
        if let explicitID {
            activeIDs = [explicitID]
            return
        }

        activeIDs = Set(candidates.compactMap { id, candidate in
            let visibilityThreshold: CGFloat = activeIDs.contains(id) ? 0.1 : 0.2
            return candidate.visibleFraction >= visibilityThreshold && candidate.isEligible
                ? id
                : nil
        })
    }

    private static var activeViewport: CGRect? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .bounds
    }
}

@MainActor
final class InlineGIFPlaybackSuspension {
    private weak var store: InlineGIFPlaybackStore?
    private let id = UUID()

    init(store: InlineGIFPlaybackStore) {
        self.store = store
        store.activate(id)
    }

    func invalidate() {
        store?.deactivate(id)
        store = nil
    }

    deinit {
        guard let store else { return }
        let id = id
        Task { @MainActor in
            store.deactivate(id)
        }
    }
}

struct AnimatedGIFView: View {
    enum Activation: Equatable {
        case whenVisible
        case onAppear
    }

    fileprivate let source: AnimatedGIFSource
    let activation: Activation
    let limits: GIFDecoder.Limits
    let posterURL: URL?
    private let externalURLOpener: ExternalMediaURLOpener
    private let onMediaTap: (() -> Void)?
    private let onMediaLongPress: (() -> Void)?
    private let mediaActionAccessibility: MediaActionAccessibility
    @Environment(InlineGIFPlaybackStore.self) private var playbackStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var loadState: LoadState = .loading
    @State private var requestID = UUID()
    @State private var playbackID = UUID()

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed
        case tooLarge

        var allowsMediaPresentation: Bool {
            self != .failed
        }
    }

    init(
        url: URL,
        posterURL: URL? = nil,
        limits: GIFDecoder.Limits = .inline,
        activation: Activation = .whenVisible,
        externalURLOpener: ExternalMediaURLOpener = .system,
        onMediaTap: (() -> Void)? = nil,
        onMediaLongPress: (() -> Void)? = nil,
        mediaActionAccessibility: MediaActionAccessibility = .openGIF
    ) {
        source = .remote(url)
        self.posterURL = posterURL
        self.limits = limits
        self.activation = activation
        self.externalURLOpener = externalURLOpener
        self.onMediaTap = onMediaTap
        self.onMediaLongPress = onMediaLongPress
        self.mediaActionAccessibility = mediaActionAccessibility
    }

#if DEBUG
    init(
        data: Data,
        limits: GIFDecoder.Limits = .inline,
        activation: Activation = .onAppear,
        externalURLOpener: ExternalMediaURLOpener = .system,
        onMediaTap: (() -> Void)? = nil,
        onMediaLongPress: (() -> Void)? = nil,
        mediaActionAccessibility: MediaActionAccessibility = .openGIF
    ) {
        source = .data(data)
        posterURL = nil
        self.limits = limits
        self.activation = activation
        self.externalURLOpener = externalURLOpener
        self.onMediaTap = onMediaTap
        self.onMediaLongPress = onMediaLongPress
        self.mediaActionAccessibility = mediaActionAccessibility
    }
#endif

    var body: some View {
        let isActive = scenePhase == .active && playbackStore.isActive(playbackID)

        ZStack {
            interactiveMediaLayer(isActive: isActive)

            if loadState == .tooLarge {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                    Text(limits == .inline
                         ? "GIF is too large to animate here"
                         : "GIF is too large to animate safely")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    if let url = source.remoteURL {
                        Button {
                            externalURLOpener.open(url)
                        } label: {
                            Label("Open in Browser", systemImage: "arrow.up.right.square")
                                .font(.caption.weight(.semibold))
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .contentShape(Rectangle())
                        .accessibilityHint("Opens the GIF in your default browser")
                    }
                }
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                .zIndex(1)
            } else if loadState == .failed {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(Theme.textMuted)
                    Text("Couldn't load GIF")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                    Button("Retry") {
                        if activation == .whenVisible {
                            playbackStore.setCandidateEligible(true, id: playbackID)
                        }
                        loadState = .loading
                        requestID = UUID()
                    }
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 44)
                    .padding(.horizontal, 8)
                }
            } else {
                switch loadState {
                case .loading:
                    ProgressView().tint(Theme.primary)
                case .failed, .tooLarge:
                    EmptyView()
                case .loaded:
                    EmptyView()
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            guard activation == .whenVisible else { return }
            playbackStore.updateCandidate(playbackID, frame: frame)
        }
        .onAppear {
            if activation == .onAppear {
                playbackStore.activate(playbackID)
            }
        }
        .onChange(of: loadState) { _, newState in
            guard activation == .whenVisible else { return }
            playbackStore.setCandidateEligible(
                newState != .failed && newState != .tooLarge,
                id: playbackID
            )
        }
        .onDisappear {
            if activation == .onAppear {
                playbackStore.deactivate(playbackID)
            } else {
                playbackStore.removeCandidate(playbackID)
            }
        }
    }

    @ViewBuilder
    private func interactiveMediaLayer(isActive: Bool) -> some View {
        if let onMediaTap, let onMediaLongPress {
            mediaLayer(isActive: isActive)
                .contentShape(Rectangle())
                .gesture(
                    LongPressGesture()
                        .exclusively(before: TapGesture())
                        .onEnded { value in
                            switch value {
                            case .first:
                                onMediaLongPress()
                            case .second:
                                guard loadState.allowsMediaPresentation else { return }
                                onMediaTap()
                            }
                        }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(mediaActionAccessibility.label)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(mediaActionAccessibility.hint)
                .accessibilityAction {
                    guard loadState.allowsMediaPresentation else { return }
                    onMediaTap()
                }
                .accessibilityAction(named: Text("Select comment text")) {
                    onMediaLongPress()
                }
        } else if let onMediaTap {
            Button(action: onMediaTap) {
                mediaLayer(isActive: isActive)
            }
            .buttonStyle(.plain)
            .disabled(!loadState.allowsMediaPresentation)
            .accessibilityLabel(mediaActionAccessibility.label)
            .accessibilityHint(mediaActionAccessibility.hint)
        } else if let onMediaLongPress {
            mediaLayer(isActive: isActive)
                .contentShape(Rectangle())
                .onLongPressGesture(perform: onMediaLongPress)
                .accessibilityAction(named: Text("Select comment text")) {
                    onMediaLongPress()
                }
        } else {
            mediaLayer(isActive: isActive)
        }
    }

    private func mediaLayer(isActive: Bool) -> some View {
        ZStack {
            poster

            AnimatedGIFRepresentable(
                source: source,
                requestID: requestID,
                isActive: isActive,
                limits: limits,
                loadState: $loadState
            )
            .opacity(isActive && loadState == .loaded ? 1 : 0)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var poster: some View {
        if let posterURL = staticPosterURL {
            AsyncImage(url: posterURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    Theme.surfaceElevated
                }
            }
        } else {
            Theme.surfaceElevated
        }
    }

    private var staticPosterURL: URL? {
        guard let posterURL,
              posterURL != source.remoteURL,
              posterURL.pathExtension.caseInsensitiveCompare("gif") != .orderedSame else {
            return nil
        }
        return posterURL
    }
}

private struct AnimatedGIFRepresentable: UIViewRepresentable {
    let source: AnimatedGIFSource
    let requestID: UUID
    let isActive: Bool
    let limits: GIFDecoder.Limits
    @Binding var loadState: AnimatedGIFView.LoadState

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        context.coordinator.imageView = imageView
        context.coordinator.onStateChange = { state in
            loadState = state
        }
        if isActive {
            context.coordinator.load(source: source, requestID: requestID, limits: limits)
        }
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        context.coordinator.imageView = imageView
        context.coordinator.onStateChange = { state in
            loadState = state
        }
        guard isActive else {
            context.coordinator.cancel()
            return
        }
        if context.coordinator.currentSource != source
            || context.coordinator.currentRequestID != requestID
            || context.coordinator.currentLimits != limits {
            context.coordinator.load(source: source, requestID: requestID, limits: limits)
        }
    }

    static func dismantleUIView(_ imageView: UIImageView, coordinator: Coordinator) {
        coordinator.cancel()
        imageView.image = nil
    }

    @MainActor
    final class Coordinator {
        weak var imageView: UIImageView?
        var currentSource: AnimatedGIFSource?
        var currentRequestID: UUID?
        var currentLimits: GIFDecoder.Limits?
        var onStateChange: ((AnimatedGIFView.LoadState) -> Void)?
        private var loadTask: Task<Void, Never>?

        deinit { loadTask?.cancel() }

        func load(
            source: AnimatedGIFSource,
            requestID: UUID,
            limits: GIFDecoder.Limits
        ) {
            loadTask?.cancel()
            imageView?.image = nil
            currentSource = source
            currentRequestID = requestID
            currentLimits = limits

            loadTask = Task { [weak self] in
                guard let self,
                      self.currentSource == source,
                      self.currentRequestID == requestID else { return }
                self.onStateChange?(.loading)

                do {
                    let decoded: GIFDecoder.DecodedImage
                    switch source {
                    case .remote(let url):
                        decoded = try await GIFImageLoader.load(from: url, limits: limits)
#if DEBUG
                    case .data(let data):
                        decoded = try await GIFImageLoader.load(data: data, limits: limits)
#endif
                    }
                    try Task.checkCancellation()
                    guard self.currentSource == source,
                          self.currentRequestID == requestID else { return }
                    self.imageView?.image = decoded.image
                    self.onStateChange?(.loaded)
                } catch is CancellationError {
                } catch GIFImageLoader.Failure.tooLarge {
                    guard self.currentSource == source,
                          self.currentRequestID == requestID else { return }
                    self.onStateChange?(.tooLarge)
                } catch {
                    guard self.currentSource == source,
                          self.currentRequestID == requestID else { return }
                    self.onStateChange?(.failed)
                }
            }
        }

        func cancel() {
            loadTask?.cancel()
            loadTask = nil
            currentSource = nil
            currentRequestID = nil
            currentLimits = nil
            onStateChange = nil
            imageView?.image = nil
        }
    }
}
