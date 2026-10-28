import SwiftUI

struct CatalogView: View {
    let section: CatalogSection

    @State private var filter: CatalogFilter = .last
    @State private var loader = PagedLoader()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 50) {
                Picker("Сортировка", selection: $filter) {
                    ForEach(CatalogFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 1100)
                .focusSection()

                MediaGrid(items: loader.items) { await loader.loadMore() }
                PagedFooter(loader: loader)
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .task(id: filter) {
            let key = filter.rawValue
            guard loader.key != key || (loader.items.isEmpty && loader.error == nil) else { return }
            let section = section, filter = filter
            loader.reset(key: key) { page in
                try await RezkaClient.shared.catalog(section, filter: filter, page: page)
            }
            await loader.loadMore()
        }
    }
}
