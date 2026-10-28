import SwiftUI

struct PosterImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case let .success(image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .failure:
                placeholder(icon: "film")
            default:
                placeholder(icon: nil)
            }
        }
        .clipped()
    }

    private func placeholder(icon: String?) -> some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.18), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
            if let icon {
                Image(systemName: icon).font(.system(size: 50)).foregroundStyle(.secondary)
            }
        }
    }
}

struct PosterCard: View {
    let item: MediaItem
    var width: CGFloat = 250
    /// When set, a long press on the card offers to remove it from "continue watching".
    var onRemoveFromContinue: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            removable(NavigationLink(value: item) {
                PosterImage(url: item.posterURL)
                    .frame(width: width, height: width * 1.5)
                    .overlay(alignment: .bottomLeading) {
                        if let badge = item.badge {
                            Text(badge)
                                .font(.system(size: 18, weight: .semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.75), in: Capsule())
                                .padding(10)
                        }
                    }
            }
            .buttonStyle(.card))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 24, weight: .medium))
                    .lineLimit(2)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .frame(width: width)
    }

    @ViewBuilder
    private func removable(_ card: some View) -> some View {
        if let onRemoveFromContinue {
            card.contextMenu {
                Button(role: .destructive, action: onRemoveFromContinue) {
                    Label("Убрать из «Продолжить просмотр»", systemImage: "trash")
                }
            }
        } else {
            card
        }
    }
}

/// A titled horizontal shelf of posters.
struct MediaRow: View {
    let title: String
    let items: [MediaItem]
    var onRemoveFromContinue: ((MediaItem) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .font(.title3.bold())
                .padding(.horizontal, 80)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 48) {
                    ForEach(items) { item in
                        PosterCard(item: item, onRemoveFromContinue: onRemoveFromContinue.map { remove in { remove(item) } })
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

/// A vertical grid of posters that asks for more when its last item appears.
struct MediaGrid: View {
    let items: [MediaItem]
    var onReachEnd: () async -> Void = {}

    private let columns = Array(repeating: GridItem(.fixed(250), spacing: 48, alignment: .top), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 60) {
            ForEach(items) { item in
                PosterCard(item: item)
                    .onAppear {
                        if item.id == items.last?.id {
                            Task { await onReachEnd() }
                        }
                    }
            }
        }
    }
}

struct ErrorStateView: View {
    let error: Error
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 70))
                .foregroundStyle(.yellow)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 1000)
            Button("Повторить") { Task { await retry() } }
        }
        .padding(60)
    }
}

struct EmptyStateView: View {
    let text: String
    var icon = "tray"

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: icon).font(.system(size: 70)).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary)
        }
        .padding(60)
    }
}

/// Footer for paged grids: spinner, error with retry, or empty state.
struct PagedFooter: View {
    let loader: PagedLoader
    var emptyText = "Ничего не найдено"

    var body: some View {
        Group {
            if loader.isLoading {
                ProgressView().padding(40)
            } else if let error = loader.error {
                ErrorStateView(error: error) { await loader.loadMore() }
            } else if loader.items.isEmpty, !loader.hasMore {
                EmptyStateView(text: emptyText)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

extension View {
    func mediaDestinations() -> some View {
        navigationDestination(for: MediaItem.self) { DetailsView(item: $0) }
    }
}

extension Double {
    /// `754` → `12:34`, `3723` → `1:02:03`.
    var playbackTime: String {
        let total = Int(self)
        let hours = total / 3600, minutes = total / 60 % 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
