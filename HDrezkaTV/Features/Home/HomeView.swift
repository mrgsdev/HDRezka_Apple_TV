import SwiftUI

@MainActor
@Observable
final class HomeModel {
    struct Shelf: Identifiable {
        let title: String
        let items: [MediaItem]
        var id: String { title }
        var isContinue: Bool { title == HomeModel.continueTitle }
    }

    private(set) var shelves: [Shelf] = []
    private(set) var isLoading = false
    private(set) var error: Error?
    /// Bumped per load so a superseded or cancelled load never overwrites a newer result.
    private var generation = 0

    nonisolated static let continueTitle = "Продолжить просмотр"
    private static let sources: [(String, CatalogSection?, CatalogFilter)] = [
        ("Новинки", nil, .last),
        ("Популярные фильмы", .films, .popular),
        ("Популярные сериалы", .series, .popular),
        ("Сейчас смотрят", .films, .watching),
        ("Мультфильмы", .cartoons, .popular),
        ("Аниме", .animation, .popular),
    ]

    func loadIfNeeded() async {
        if shelves.isEmpty { await load() }
    }

    func load() async {
        // SwiftUI may start and immediately cancel this task on first layout; don't send that burst.
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }

        generation += 1
        let current = generation
        isLoading = true
        error = nil

        let continueTitle = Self.continueTitle
        let titles = [continueTitle] + Self.sources.map(\.0)
        var loaded: [String: [MediaItem]] = [:]
        var firstError: Error?

        // Shelves appear as they arrive; RezkaClient limits how many requests run at once.
        await withTaskGroup(of: (String, Result<[MediaItem], Error>).self) { group in
            group.addTask {
                do { return (continueTitle, .success(try await RezkaClient.shared.continueWatching())) }
                catch { return (continueTitle, .failure(error)) }
            }
            for source in Self.sources {
                group.addTask {
                    do { return (source.0, .success(try await RezkaClient.shared.catalog(source.1, filter: source.2).items)) }
                    catch { return (source.0, .failure(error)) }
                }
            }
            for await (title, result) in group {
                guard current == generation, !Task.isCancelled else { continue }
                switch result {
                case let .success(items):
                    loaded[title] = items
                    shelves = titles.compactMap { title in
                        loaded[title].flatMap { $0.isEmpty ? nil : Shelf(title: title, items: $0) }
                    }
                case let .failure(error) where !error.isCancellation && title != Self.continueTitle:
                    firstError = firstError ?? error
                default:
                    break
                }
            }
        }

        guard current == generation, !Task.isCancelled else { return }
        if shelves.isEmpty, let firstError {
            error = firstError
            AuthSession.shared.handle(firstError)
        }
        isLoading = false
    }

    /// Re-reads only "continue watching", e.g. after the player closed.
    func refreshContinue() async {
        guard !shelves.isEmpty, let items = try? await RezkaClient.shared.continueWatching() else { return }
        setContinue(items)
    }

    private func setContinue(_ items: [MediaItem]) {
        shelves.removeAll(where: \.isContinue)
        if !items.isEmpty {
            shelves.insert(Shelf(title: Self.continueTitle, items: items), at: 0)
        }
    }
}

struct HomeView: View {
    @State private var model = HomeModel()

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 60) {
                ForEach(model.shelves) { shelf in
                    MediaRow(title: shelf.title, items: shelf.items)
                }
            }
            .padding(.vertical, 40)
        }
        .overlay {
            if model.shelves.isEmpty {
                if let error = model.error {
                    ErrorStateView(error: error) { await model.load() }
                } else {
                    ProgressView()
                }
            }
        }
        .task { await model.loadIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .watchHistoryChanged)) { _ in
            Task { await model.refreshContinue() }
        }
    }
}
