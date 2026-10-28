import SwiftUI

struct BookmarksView: View {
    @State private var folders: [BookmarkFolder] = []
    @State private var selectedFolder: String?
    @State private var foldersError: Error?
    @State private var isLoadingFolders = false
    @State private var loader = PagedLoader()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 50) {
                if !folders.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 24) {
                            ForEach(folders) { folder in
                                Button {
                                    selectedFolder = folder.id
                                } label: {
                                    HStack(spacing: 12) {
                                        if folder.id == selectedFolder {
                                            Image(systemName: "checkmark")
                                        }
                                        Text(folder.name)
                                        if let count = folder.count {
                                            Text("\(count)").foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 20)
                    }
                    .scrollClipDisabled()
                    .focusSection()
                }

                MediaGrid(items: loader.items) { await loader.loadMore() }
                if selectedFolder != nil {
                    PagedFooter(loader: loader, emptyText: "В этой папке пока пусто")
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .overlay {
            if folders.isEmpty {
                if isLoadingFolders {
                    ProgressView()
                } else if let foldersError {
                    ErrorStateView(error: foldersError) { await loadFolders() }
                } else {
                    EmptyStateView(text: "Закладок пока нет. Добавляйте их на сайте — они появятся здесь.", icon: "bookmark")
                }
            }
        }
        .task {
            if folders.isEmpty { await loadFolders() }
        }
        .task(id: selectedFolder) {
            guard let folder = selectedFolder, loader.key != folder else { return }
            loader.reset(key: folder) { page in
                try await RezkaClient.shared.bookmarks(folder: folder, page: page)
            }
            await loader.loadMore()
        }
    }

    private func loadFolders() async {
        isLoadingFolders = true
        foldersError = nil
        do {
            folders = try await RezkaClient.shared.bookmarkFolders()
            if selectedFolder == nil { selectedFolder = folders.first?.id }
        } catch where !error.isCancellation {
            foldersError = error
            AuthSession.shared.handle(error)
        } catch {}
        isLoadingFolders = false
    }
}
