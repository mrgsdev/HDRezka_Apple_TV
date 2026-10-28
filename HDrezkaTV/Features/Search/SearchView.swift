import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var loader = PagedLoader()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                MediaGrid(items: loader.items) { await loader.loadMore() }
                if loader.key != nil {
                    PagedFooter(loader: loader, emptyText: "По запросу «\(loader.key ?? "")» ничего не найдено")
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .searchable(text: $query, prompt: "Фильмы, сериалы, мультфильмы")
        .task(id: query) {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2 else {
                loader.clear()
                return
            }
            guard text != loader.key else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            loader.reset(key: text) { page in
                try await RezkaClient.shared.search(text, page: page)
            }
            await loader.loadMore()
        }
    }
}
