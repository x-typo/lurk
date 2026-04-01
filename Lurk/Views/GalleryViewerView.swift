import SwiftUI
import UIKit

struct GalleryViewerView: View {
    let items: [GalleryMedia]
    @State private var currentPage = 0
    @State private var dragOffset: CGSize = .zero
    @State private var dragAxis: Axis?
    @State private var saveState: SaveState = .idle
    @Environment(\.dismiss) private var dismiss

    private let dismissThreshold: CGFloat = 150

    enum SaveState {
        case idle, saving, saved, failed
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
                    if item.isAnimated {
                        AnimatedGIFView(url: item.url)
                            .aspectRatio(contentMode: .fit)
                            .tag(item.id)
                    } else {
                        AsyncImage(url: item.url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(Theme.textMuted)
                            default:
                                ProgressView().tint(Theme.primary)
                            }
                        }
                        .tag(item.id)
                    }
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
                        saveState = .saving
                        Task {
                            guard let item = currentItem else {
                                saveState = .failed
                                try? await Task.sleep(for: .seconds(1.5))
                                saveState = .idle
                                return
                            }
                            let result = item.isAnimated
                                ? await MediaSaver.saveImageData(from: item.url)
                                : await MediaSaver.saveImage(from: item.url)
                            saveState = result == .saved ? .saved : .failed
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
                            guard let item = currentItem,
                                  let (data, _) = try? await URLSession.shared.data(from: item.url) else { return }
                            let shareItem: Any
                            if item.isAnimated {
                                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gif")
                                guard (try? data.write(to: tempURL)) != nil else { return }
                                shareItem = tempURL
                            } else {
                                guard let image = UIImage(data: data) else { return }
                                shareItem = image
                            }
                            let ac = UIActivityViewController(activityItems: [shareItem], applicationActivities: nil)
                            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               var presenter = scene.keyWindow?.rootViewController {
                                while let next = presenter.presentedViewController {
                                    presenter = next
                                }
                                ac.popoverPresentationController?.sourceView = presenter.view
                                ac.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                                presenter.present(ac, animated: true)
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: currentPage) { _, _ in
            saveState = .idle
        }
    }
}
