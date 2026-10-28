import SwiftUI

@MainActor
@Observable
final class BookmarksModel {
    private(set) var folders: [BookmarkFolder] = []
    var selectedFolderId: String?
    private(set) var isLoadingFolders = false
    private(set) var foldersError: Error?
    var actionError: String?
    /// Set when bookmarks changed elsewhere (a details page); the screen reloads when shown again.
    var isStale = false
    let loader = PagedLoader()

    var selectedFolder: BookmarkFolder? {
        folders.first { $0.id == selectedFolderId }
    }

    func loadFolders() async {
        isLoadingFolders = true
        foldersError = nil
        do {
            folders = try await RezkaClient.shared.bookmarkFolders()
            if selectedFolder == nil { selectedFolderId = folders.first?.id }
        } catch where !error.isCancellation {
            foldersError = error
            AuthSession.shared.handle(error)
        } catch {}
        isLoadingFolders = false
    }

    func showSelectedFolder(force: Bool = false) async {
        guard let folder = selectedFolderId else {
            loader.clear()
            return
        }
        guard force || loader.key != folder else { return }
        loader.reset(key: folder) { page in
            try await RezkaClient.shared.bookmarks(folder: folder, page: page)
        }
        await loader.loadMore()
    }

    func reload() async {
        await loadFolders()
        await showSelectedFolder(force: true)
    }

    // MARK: Folders

    func createFolder(named name: String) async {
        guard let name = name.nonEmpty else { return }
        do {
            let folder = try await RezkaClient.shared.createBookmarkFolder(name: name)
            // Reload so the folder lands where the site sorts it.
            await loadFolders()
            if !folders.contains(where: { $0.id == folder.id }) { folders.insert(folder, at: 0) }
            selectedFolderId = folder.id
        } catch {
            report(error)
        }
    }

    func renameSelectedFolder(to name: String) async {
        guard let folder = selectedFolder, let name = name.nonEmpty, name != folder.name else { return }
        do {
            try await RezkaClient.shared.renameBookmarkFolder(id: folder.id, name: name)
            update(folder.id) { BookmarkFolder(id: $0.id, name: name, count: $0.count) }
        } catch {
            report(error)
        }
    }

    func deleteSelectedFolder() async {
        guard let folder = selectedFolder else { return }
        do {
            try await RezkaClient.shared.deleteBookmarkFolder(id: folder.id)
            folders.removeAll { $0.id == folder.id }
            selectedFolderId = folders.first?.id
        } catch {
            report(error)
        }
    }

    // MARK: Titles

    func remove(_ item: MediaItem) async {
        guard let folder = selectedFolder, let postId = RezkaParser.idFromPath(item.path) else { return }
        do {
            try await RezkaClient.shared.removeBookmark(postId: postId, folder: folder.id)
            loader.remove(id: item.id)
            update(folder.id) { BookmarkFolder(id: $0.id, name: $0.name, count: $0.count.map { max($0 - 1, 0) }) }
        } catch {
            report(error)
        }
    }

    func move(_ item: MediaItem, to target: BookmarkFolder) async {
        guard let folder = selectedFolder, let postId = RezkaParser.idFromPath(item.path) else { return }
        do {
            try await RezkaClient.shared.moveBookmark(postId: postId, from: folder.id, to: target.id)
            loader.remove(id: item.id)
            // Counts change on both sides; a title already in the target is not duplicated, so ask the site.
            folders = (try? await RezkaClient.shared.bookmarkFolders()) ?? folders
        } catch {
            report(error)
        }
    }

    private func update(_ id: String, _ change: (BookmarkFolder) -> BookmarkFolder) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index] = change(folders[index])
    }

    private func report(_ error: Error) {
        guard !error.isCancellation else { return }
        actionError = error.localizedDescription
        AuthSession.shared.handle(error)
    }
}

struct BookmarksView: View {
    private enum Editor {
        case create, rename
    }

    @State private var model = BookmarksModel()
    @State private var editor: Editor?
    @State private var folderName = ""
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 50) {
                if !model.folders.isEmpty {
                    folderBar
                }

                MediaGrid(items: model.loader.items, onReachEnd: { await model.loader.loadMore() }, actions: actions(for:))
                if model.selectedFolderId != nil {
                    PagedFooter(loader: model.loader, emptyText: "В этой папке пока пусто. Добавляйте сюда фильмы и сериалы кнопкой «В закладки» в их карточке.")
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .overlay {
            if model.folders.isEmpty {
                if model.isLoadingFolders {
                    ProgressView()
                } else if let error = model.foldersError {
                    ErrorStateView(error: error) { await model.loadFolders() }
                } else {
                    VStack(spacing: 10) {
                        EmptyStateView(text: "Закладок пока нет. Создайте папку и добавляйте в неё фильмы и сериалы кнопкой «В закладки» в их карточке.",
                                       icon: "bookmark")
                        Button("Создать папку") { startEditing(.create) }
                    }
                }
            }
        }
        .task {
            if model.folders.isEmpty { await model.loadFolders() }
        }
        .task(id: model.selectedFolderId) {
            await model.showSelectedFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarksChanged)) { _ in
            model.isStale = true
        }
        .onAppear {
            guard model.isStale else { return }
            model.isStale = false
            Task { await model.reload() }
        }
        .alert(editor == .rename ? "Переименовать папку" : "Новая папка", isPresented: Binding(
            get: { editor != nil },
            set: { if !$0 { editor = nil } }
        )) {
            TextField("Название", text: $folderName)
            Button(editor == .rename ? "Сохранить" : "Создать") {
                // The alert resets `editor` as it closes, so read it now.
                let mode = editor, name = folderName
                Task {
                    if mode == .rename {
                        await model.renameSelectedFolder(to: name)
                    } else {
                        await model.createFolder(named: name)
                    }
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog(
            "Удалить папку «\(model.selectedFolder?.name ?? "")»?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) { Task { await model.deleteSelectedFolder() } }
        } message: {
            if let count = model.selectedFolder?.count, count > 0 {
                Text("Закладки в ней (\(count)) тоже удалятся.")
            }
        }
        .alert("Не получилось", isPresented: Binding(
            get: { model.actionError != nil },
            set: { if !$0 { model.actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
    }

    private var folderBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 24) {
                ForEach(model.folders) { folder in
                    Button {
                        model.selectedFolderId = folder.id
                    } label: {
                        HStack(spacing: 12) {
                            if folder.id == model.selectedFolderId {
                                Image(systemName: "checkmark")
                            }
                            Text(folder.name)
                            if let count = folder.count {
                                Text("\(count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let folder = model.selectedFolder {
                    Menu {
                        Button {
                            startEditing(.rename, name: folder.name)
                        } label: {
                            Label("Переименовать", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Удалить папку", systemImage: "trash")
                        }
                    } label: {
                        Label("Изменить", systemImage: "ellipsis.circle")
                    }
                }

                Button {
                    startEditing(.create)
                } label: {
                    Label("Новая папка", systemImage: "plus")
                }
            }
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    /// Long-press menu on a poster: remove it from the folder or move it to another one.
    private func actions(for item: MediaItem) -> [CardAction] {
        guard let folder = model.selectedFolder else { return [] }
        let remove = CardAction(title: "Убрать из «\(folder.name)»", systemImage: "trash", isDestructive: true) {
            Task { await model.remove(item) }
        }
        let moves = model.folders.filter { $0.id != folder.id }.map { target in
            CardAction(title: "Перенести в «\(target.name)»", systemImage: "folder") {
                Task { await model.move(item, to: target) }
            }
        }
        return [remove] + moves
    }

    private func startEditing(_ mode: Editor, name: String = "") {
        folderName = name
        editor = mode
    }
}
