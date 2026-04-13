import SwiftUI

struct PostCardView: View {
    let post: Post
    var onHide: ((String) -> Void)?
    var onShowDetail: (() -> Void)?
    var onShowSubreddit: (() -> Void)?
    var onShowGallery: (() -> Void)?

    @State private var offset: CGFloat = 0
    @State private var dragAxis: Axis?
    @State private var collapsing = false
    @Environment(\.openURL) private var openURL

    private let swipeThreshold: CGFloat = 100
    private let swipeHideOffset: CGFloat = 500

    var body: some View {
        ZStack {
            (offset > 0 ? Theme.swipeOpen : offset < 0 ? Theme.swipeHide : Color.clear)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(post.subredditNamePrefixed)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                        .onTapGesture { onShowSubreddit?() }
                    Text("\u{2022}")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                    Text(Formatters.timeAgo(post.createdUtc))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textMuted)
                }

                Text(post.title)
                    .font(.body)
                    .foregroundStyle(Theme.text)
                    .lineLimit(4)

                if let imageURL = post.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(post.imageAspectRatio, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure:
                            EmptyView()
                        default:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.surfaceElevated)
                                .aspectRatio(post.imageAspectRatio ?? 16/9, contentMode: .fit)
                                .overlay { ProgressView().tint(Theme.textMuted) }
                        }
                    }
                    .overlay(alignment: .center) {
                        if post.isVideo {
                            Image(systemName: "play.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if post.galleryItems.count > 1 {
                            GalleryDotIndicator(count: post.galleryItems.count)
                        }
                    }
                    .onTapGesture {
                        if post.isGallery {
                            onShowGallery?()
                        } else {
                            onShowDetail?()
                        }
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "arrow.up")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(Formatters.score(post.score))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Text("\u{2022}")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                    Text("\(Formatters.score(post.numComments)) comments")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .offset(x: offset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if dragAxis == nil {
                            dragAxis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                        }
                        guard dragAxis == .horizontal else { return }
                        offset = value.translation.width
                    }
                    .onEnded { value in
                        defer { dragAxis = nil }
                        guard dragAxis == .horizontal else { return }
                        if value.translation.width > swipeThreshold {
                            withAnimation(.spring()) { offset = 0 }
                            openURL(post.redditURL)
                        } else if value.translation.width < -swipeThreshold, onHide != nil {
                            withAnimation(.easeIn(duration: 0.2)) {
                                offset = -swipeHideOffset
                            }
                            Task {
                                try? await Task.sleep(for: .seconds(0.2))
                                withAnimation(.easeOut(duration: 0.25)) {
                                    collapsing = true
                                }
                                try? await Task.sleep(for: .seconds(0.25))
                                onHide?(post.id)
                            }
                        } else {
                            withAnimation(.spring()) { offset = 0 }
                        }
                    }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(height: collapsing ? 0 : nil)
        .clipped()
        .opacity(collapsing ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { onShowDetail?() }
    }
}
