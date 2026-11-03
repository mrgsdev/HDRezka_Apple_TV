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

    @FocusState private var isFocused: Bool
    /// The site's card for the title, shown once the poster has kept the focus a moment; the screen
    /// draws it, over every shelf, from where this card reports its bounds.
    @State private var showsInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            withActions(NavigationLink(value: item) {
                PosterImage(url: item.posterURL)
                    .frame(width: width, height: width * 1.5)
                    .overlay(alignment: .topTrailing) { KindBadge(kind: item.kind) }
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
            .buttonStyle(.card)
            .focused($isFocused))

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
        .anchorPreference(key: QuickInfoAnchor.Key.self, value: .bounds) { showsInfo ? QuickInfoAnchor(item: item, bounds: $0) : nil }
        // Like pointing at a poster on the site: a moment's rest on it shows the card, moving on hides it.
        .task(id: isFocused) {
            guard isFocused, RezkaParser.idFromPath(item.path) != nil else {
                withAnimation(.easeOut(duration: 0.15)) { showsInfo = false }
                return
            }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { showsInfo = true }
        }
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

/// «Фильм», «Сериал»… in a poster's top corner, as the site marks its posters.
struct KindBadge: View {
    let kind: MediaKind

    var body: some View {
        if let title = kind.title {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: kind.symbol)
            }
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor, in: UnevenRoundedRectangle(bottomLeadingRadius: 12))
        }
    }
}

extension MediaKind {
    var symbol: String {
        switch self {
        case .film: "video.fill"
        case .series: "tv.fill"
        case .cartoon: "sparkles.tv.fill"
        case .anime: "wand.and.stars"
        case .show: "theatermasks.fill"
        case .unknown: "questionmark"
        }
    }
}

/// Where a poster resting under the focus is, for the screen to draw the site's card beside it.
struct QuickInfoAnchor {
    let item: MediaItem
    let bounds: Anchor<CGRect>

    struct Key: PreferenceKey {
        static var defaultValue: QuickInfoAnchor? { nil }
        static func reduce(value: inout QuickInfoAnchor?, nextValue: () -> QuickInfoAnchor?) {
            value = value ?? nextValue()
        }
    }
}

extension View {
    /// Draws the site's card beside the poster that has kept the focus a moment: on the poster's right,
    /// or its left near the right edge of the screen, above every shelf on the page.
    func quickInfoLayer() -> some View {
        overlayPreferenceValue(QuickInfoAnchor.Key.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    QuickInfoPlacement(anchor: anchor, proxy: proxy)
                        .id(anchor.item.id)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.2), value: anchor?.item.id)
        }
    }
}

/// The card level with the poster's top, kept whole on screen by its own height.
private struct QuickInfoPlacement: View {
    let anchor: QuickInfoAnchor
    let proxy: GeometryProxy

    @State private var height: CGFloat = 520

    var body: some View {
        let rect = proxy[anchor.bounds]
        let onLeft = rect.midX > proxy.size.width * 0.57
        QuickInfoView(item: anchor.item)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .offset(x: onLeft ? rect.minX - 36 - QuickInfoView.width : rect.maxX + 36,
                    y: max(min(rect.minY - 10, proxy.size.height - height - 40), 40))
    }
}

/// The site's hover card for a title: its rating, the start of the description, genres, people and
/// IMDb, loaded once per title while the app runs.
struct QuickInfoView: View {
    let item: MediaItem

    static let width: CGFloat = 640

    @State private var info: QuickInfo?
    @State private var failed = false

    @MainActor private static var cache: [String: QuickInfo] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let info {
                content(info)
            } else if failed {
                Text("Не удалось загрузить информацию.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 16) {
                    ProgressView()
                    Text("Загружаем…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(32)
        .frame(width: Self.width, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30))
        .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ info: QuickInfo) -> some View {
        Text(info.title.isEmpty ? item.title : info.title)
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
        if let rating = info.rating {
            HStack(spacing: 10) {
                if let label = info.ratingLabel {
                    Text(verbatim: label + ":").foregroundStyle(.secondary)
                }
                Text(verbatim: rating.value).bold()
                Text(verbatim: "(\(rating.votes))").foregroundStyle(.secondary)
            }
            .font(.callout)
        }
        if !info.description.isEmpty {
            Text(info.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(info.rows, id: \.self) { row in
            (Text(verbatim: row.label + ": ").foregroundStyle(.secondary) + Text(verbatim: row.values.joined(separator: ", ")))
                .font(.caption)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        if info.imdb != nil || info.kinopoisk != nil {
            HStack(spacing: 30) {
                if let imdb = info.imdb { score("IMDb", imdb) }
                if let kinopoisk = info.kinopoisk { score("Кинопоиск", kinopoisk) }
            }
            .font(.caption)
        }
    }

    private func score(_ name: String, _ score: QuickInfo.Score) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: name + ":").foregroundStyle(.secondary)
            Text(verbatim: score.value).bold()
            Text(verbatim: "(\(score.votes))").foregroundStyle(.secondary)
        }
    }

    private func load() async {
        guard let postId = RezkaParser.idFromPath(item.path) else { failed = true; return }
        if let cached = Self.cache[postId] {
            info = cached
            return
        }
        do {
            let loaded = try await RezkaClient.shared.quickInfo(postId: postId)
            Self.cache[postId] = loaded
            info = loaded
        } catch {
            if !error.isCancellation { failed = true }
        }
    }
}

/// A titled horizontal shelf of posters.
struct MediaRow: View {
    let title: String
    let items: [MediaItem]
    var actions: (MediaItem) -> [CardAction] = { _ in [] }

    /// Without what kid mode hides.
    private var visible: [MediaItem] { items.filter(ParentalControl.shared.allows) }

    var body: some View {
        // A shelf kid mode empties goes away with its title.
        if !visible.isEmpty {
            shelf
        }
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .font(.title3.bold())
                .padding(.horizontal, 80)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 48) {
                    ForEach(visible) { item in
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

    /// Without what kid mode hides.
    private var visible: [MediaItem] { items.filter(ParentalControl.shared.allows) }

    /// Pages loaded on its own while kid mode hid nearly everything.
    @State private var extraPages = 0
    private static let maxExtraPages = 6

    private let columns = Array(repeating: GridItem(.fixed(250), spacing: 48, alignment: .top), count: 6)

    var body: some View {
        Group {
            if !items.isEmpty, visible.isEmpty, extraPages >= Self.maxExtraPages || ParentalControl.shared.limit == nil {
                KidModeEmptyView()
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 60) {
                    ForEach(visible) { item in
                        PosterCard(item: item, actions: actions(item))
                            .onAppear {
                                if item.id == visible.last?.id {
                                    Task { await onReachEnd() }
                                }
                            }
                    }
                }
            }
        }
        // With only a few cards let through, nothing would scroll to the end to load more: look a few
        // pages further before saying there is nothing for this age.
        .task(id: items.count) {
            guard ParentalControl.shared.isOn, !items.isEmpty, visible.count < 12, extraPages < Self.maxExtraPages else { return }
            extraPages += 1
            await onReachEnd()
            // The list ended: nothing more to wait for.
            if !items.isEmpty, visible.isEmpty { extraPages = Self.maxExtraPages }
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
        quickInfoLayer()
            .navigationDestination(for: MediaItem.self) { DetailsView(item: $0).quickInfoLayer() }
            .navigationDestination(for: Listing.self) { ListingView(listing: $0).quickInfoLayer() }
            .navigationDestination(for: PersonLink.self) { PersonView(person: $0).quickInfoLayer() }
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
