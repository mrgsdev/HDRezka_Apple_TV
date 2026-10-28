import SwiftUI

/// Unlike AsyncImage, retries a load that was cancelled because the poster left the screen
/// (a shelf arriving above pushes rows out of the lazy stack) instead of keeping the failure.
struct PosterImage: View {
    let url: URL?

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image = url.flatMap(PosterCache.image(for:)) ?? image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                placeholder(icon: failed ? "film" : nil)
            }
        }
        .clipped()
        // Runs again whenever the poster reappears, which is what retries an interrupted load.
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            failed = true
            return
        }
        if let cached = PosterCache.image(for: url) {
            image = cached
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let decoded = await UIImage(data: data)?.byPreparingForDisplay() else {
                failed = true
                return
            }
            PosterCache.store(decoded, for: url)
            withAnimation(.easeOut(duration: 0.2)) { image = decoded }
        } catch {
            // A cancelled load stays a blank placeholder and is retried when the poster reappears.
            if !error.isCancellation { failed = true }
        }
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

/// Decoded posters kept in memory so rows scrolling back into view show them at once.
enum PosterCache {
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    static func store(_ image: UIImage, for url: URL) {
        let bytes = Int(image.size.width * image.scale * image.size.height * image.scale) * 4
        cache.setObject(image, forKey: url as NSURL, cost: bytes)
    }
}

/// An entry of the menu a long press on a poster opens, e.g. "remove from this list".
struct CardAction: Identifiable {
    let title: String
    let systemImage: String
    var isDestructive = false
    let perform: () -> Void

    var id: String { title }
}

struct PosterCard: View {
    let item: MediaItem
    var width: CGFloat = 250
    /// Shown on a long press; no menu when empty.
    var actions: [CardAction] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            withActions(NavigationLink(value: item) {
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
    private func withActions(_ card: some View) -> some View {
        if actions.isEmpty {
            card
        } else {
            card.contextMenu {
                ForEach(actions) { action in
                    Button(role: action.isDestructive ? .destructive : nil, action: action.perform) {
                        Label(action.title, systemImage: action.systemImage)
                    }
                }
            }
        }
    }
}

/// A titled horizontal shelf of posters.
struct MediaRow: View {
    let title: String
    let items: [MediaItem]
    var actions: (MediaItem) -> [CardAction] = { _ in [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .font(.title3.bold())
                .padding(.horizontal, 80)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 48) {
                    ForEach(items) { item in
                        PosterCard(item: item, actions: actions(item))
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
    /// After onReachEnd so a trailing closure keeps meaning onReachEnd.
    var actions: (MediaItem) -> [CardAction] = { _ in [] }

    private let columns = Array(repeating: GridItem(.fixed(250), spacing: 48, alignment: .top), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 60) {
            ForEach(items) { item in
                PosterCard(item: item, actions: actions(item))
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
            .navigationDestination(for: Listing.self) { ListingView(listing: $0) }
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
