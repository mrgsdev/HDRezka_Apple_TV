import SwiftUI

@MainActor
@Observable
final class CollectionsModel {
    private(set) var items: [MediaCollection] = []
    private(set) var isLoading = false
    private(set) var error: Error?
    private(set) var hasMore = true
    private var page = 0

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        error = nil
        do {
            let result = try await RezkaClient.shared.collections(page: page + 1)
            page += 1
            let known = Set(items.map(\.id))
            items += result.items.filter { !known.contains($0.id) }
            hasMore = result.hasMore
        } catch where !error.isCancellation {
            self.error = error
            AuthSession.shared.handle(error)
        } catch {}
        isLoading = false
    }
}

/// The site's collections ("Фильмы Netflix", "Сериалы 2024 года"…), with announcements first.
struct CollectionsView: View {
    @State private var model = CollectionsModel()

    private let columns = Array(repeating: GridItem(.fixed(380), spacing: 48, alignment: .top), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 60) {
                    CollectionCard(listing: .announcements, coverURL: nil, count: nil, icon: "megaphone")
                    ForEach(model.items) { collection in
                        CollectionCard(listing: collection.listing, coverURL: collection.coverURL, count: collection.count)
                            .onAppear {
                                if collection.id == model.items.last?.id {
                                    Task { await model.loadMore() }
                                }
                            }
                    }
                }

                Group {
                    if model.isLoading {
                        ProgressView().padding(40)
                    } else if let error = model.error {
                        ErrorStateView(error: error) { await model.loadMore() }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .task {
            if model.items.isEmpty { await model.loadMore() }
        }
    }
}

private struct CollectionCard: View {
    let listing: Listing
    let coverURL: URL?
    let count: Int?
    /// Drawn instead of a cover, for entries the site shows without one.
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NavigationLink(value: listing) {
                Group {
                    if let icon {
                        ZStack {
                            LinearGradient(colors: [Color(white: 0.24), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Image(systemName: icon).font(.system(size: 70)).foregroundStyle(.secondary)
                        }
                    } else {
                        PosterImage(url: coverURL)
                    }
                }
                .frame(width: 380, height: 220)
                .overlay(alignment: .bottomTrailing) {
                    if let count {
                        Text("\(count)")
                            .font(.system(size: 20, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.75), in: Capsule())
                            .padding(10)
                    }
                }
            }
            .buttonStyle(.card)

            Text(listing.title)
                .font(.system(size: 24, weight: .medium))
                .lineLimit(2)
                .frame(width: 380, alignment: .leading)
        }
    }
}
