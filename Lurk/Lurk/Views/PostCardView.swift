import SwiftUI

struct PostCardView: View {
    let post: Post
    var onHide: ((String) -> Void)?

    @State private var offset: CGFloat = 0
    @State private var isHorizontalDrag = false
    @State private var showDetail = false
    @Environment(\.openURL) private var openURL

    private let swipeThreshold: CGFloat = 100
    private let swipeHideOffset: CGFloat = 500

    var body: some View {
        ZStack {
            // Swipe backgrounds
            HStack(spacing: 0) {
                Theme.swipeOpen
                    .frame(width: swipeThreshold + 20)
                Spacer()
                ZStack(alignment: .trailing) {
                    Theme.swipeHide
                    Text("\u{2715}")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .padding(.trailing, 20)
                }
                .frame(width: swipeThreshold + 20)
            }

            // Card content
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack(spacing: 6) {
                    Text(post.subredditNamePrefixed)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                    Text("\u{2022}")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                    Text(Formatters.timeAgo(post.createdUtc))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textMuted)
                }

                // Title
                Text(post.title)
                    .font(.body)
                    .foregroundStyle(Theme.text)
                    .lineLimit(4)

                // Image
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
                        if post.isGallery {
                            HStack(spacing: 6) {
                                ForEach(0..<min(post.galleryCount, 5), id: \.self) { i in
                                    Circle()
                                        .fill(i == 0 ? Color.white : Color.white.opacity(0.5))
                                        .frame(width: 8, height: 8)
                                }
                                if post.galleryCount > 5 {
                                    Text("+\(post.galleryCount - 5)")
                                        .font(.caption2)
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.bottom, 10)
                        }
                    }
                }

                // Footer
                HStack(spacing: 6) {
                    Text(Formatters.score(post.score))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Text("\u{25B3}")
                        .font(.caption2)
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
                        if !isHorizontalDrag {
                            let horizontal = abs(value.translation.width)
                            let vertical = abs(value.translation.height)
                            if horizontal > vertical {
                                isHorizontalDrag = true
                            } else {
                                return
                            }
                        }
                        offset = value.translation.width
                    }
                    .onEnded { value in
                        defer { isHorizontalDrag = false }
                        guard isHorizontalDrag else { return }
                        if value.translation.width > swipeThreshold {
                            withAnimation(.spring()) { offset = 0 }
                            openURL(post.redditURL)
                        } else if value.translation.width < -swipeThreshold, onHide != nil {
                            withAnimation(.easeIn(duration: 0.2)) {
                                offset = -swipeHideOffset
                            }
                            Task {
                                try? await Task.sleep(for: .seconds(0.2))
                                onHide?(post.id)
                            }
                        } else {
                            withAnimation(.spring()) { offset = 0 }
                        }
                    }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .sheet(isPresented: $showDetail) {
            PostDetailView(post: post)
        }
    }
}
