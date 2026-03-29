import SwiftUI

struct GalleryViewerView: View {
    let urls: [URL]
    @State private var currentPage = 0
    @State private var dragOffset: CGSize = .zero
    @State private var saveState: SaveState = .idle
    @Environment(\.dismiss) private var dismiss

    private let dismissThreshold: CGFloat = 150

    enum SaveState {
        case idle, saving, saved, failed
    }

    var body: some View {
        let dragProgress = min(abs(dragOffset.height) / dismissThreshold, 1.0)

        ZStack(alignment: .topTrailing) {
            Theme.background.ignoresSafeArea()
                .opacity(1 - dragProgress * 0.5)

            TabView(selection: $currentPage) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    AsyncImage(url: url) { phase in
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
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .offset(y: dragOffset.height)
            .scaleEffect(1 - dragProgress * 0.15)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        if abs(value.translation.height) > dismissThreshold {
                            dismiss()
                        } else {
                            withAnimation(.spring()) { dragOffset = .zero }
                        }
                    }
            )

            HStack(spacing: 12) {
                Spacer()

                Button {
                    saveState = .saving
                    Task {
                        let result = await MediaSaver.saveImage(from: urls[currentPage])
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
                    .frame(width: 32, height: 32)
                }
                .disabled(saveState != .idle)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(16)

            VStack {
                Spacer()
                Text("\(currentPage + 1) / \(urls.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5))
                    .clipShape(Capsule())
                    .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: currentPage) { _, _ in
            saveState = .idle
        }
    }
}
