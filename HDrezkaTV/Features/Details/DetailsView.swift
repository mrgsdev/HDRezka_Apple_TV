import SwiftUI

struct DetailsView: View {
    let item: MediaItem

    @State private var model: DetailsModel
    @Environment(WatchProgressStore.self) private var progress
    @Environment(AuthSession.self) private var auth
    @FocusState private var isPlayFocused: Bool
    @State private var didFocusPlay = false
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var revealedSpoilers: Set<String> = []

    init(item: MediaItem) {
        self.item = item
        _model = State(initialValue: DetailsModel(item: item))
    }

    var body: some View {
        ZStack {
            switch model.state {
            case .loading:
                ProgressView()
            case let .failed(error):
                ErrorStateView(error: error) { await model.load() }
            case let .loaded(details):
                content(details)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A background never affects layout; inside the ZStack the aspect-fill poster made the
        // screen ~2900pt tall and pushed the top of the scroll view off screen.
        .background { backdrop }
        .task { await model.loadIfNeeded() }
        // While the page loads there is nothing focusable here, so focus stays on the previous
        // screen; pull it onto the play button once that button exists.
        .onChange(of: isPlayReady) { _, ready in
            guard ready, !didFocusPlay else { return }
            didFocusPlay = true
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                isPlayFocused = true
            }
        }
        .alert("Новая папка закладок", isPresented: $isCreatingFolder) {
            TextField("Название", text: $newFolderName)
            Button("Создать и добавить") {
                let name = newFolderName
                Task { await model.createBookmarkFolder(named: name) }
            }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Не получилось", isPresented: Binding(
            get: { model.bookmarkError != nil },
            set: { if !$0 { model.bookmarkError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.bookmarkError ?? "")
        }
    }

    private var backdrop: some View {
        Color.black
            .overlay {
                PosterImage(url: model.details?.posterURL ?? item.posterURL)
                    .blur(radius: 80)
                    .opacity(0.35)
            }
            .overlay(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
            .clipped()
            .ignoresSafeArea()
    }

    private func content(_ details: MediaDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 60) {
                HStack(alignment: .top, spacing: 60) {
                    PosterImage(url: details.posterURL ?? item.posterURL)
                        .frame(width: 380, height: 570)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(radius: 30)

                    VStack(alignment: .leading, spacing: 22) {
                        Text(details.title)
                            .font(.title2.bold())
                            .lineLimit(2)
                        if !details.originalTitle.isEmpty {
                            Text(details.originalTitle)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        metaLine(details)
                        if let ratings = details.info("Рейтинги") {
                            Label(ratings, systemImage: "star.fill")
                                .font(.callout)
                                .foregroundStyle(.yellow)
                        }
                        actions(details)
                            .padding(.vertical, 10)
                            .focusSection()
                        if model.translator?.isPremium == true, !auth.isPremium {
                            Label("Эта озвучка только для HDrezka Premium — без подписки покажут короткое превью. Выберите озвучку без короны.",
                                  systemImage: "crown.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if !details.description.isEmpty {
                            Text(details.description)
                                .font(.callout)
                                .lineLimit(6)
                        }
                        if let cast = details.info("В ролях") {
                            Text("В ролях: \(cast)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.horizontal, 80)
                // Full-width section so "up" from the episode row reaches the buttons beside the poster.
                .focusSection()

                if details.isSeries {
                    episodes(details)
                }

                if !details.related.isEmpty {
                    MediaRow(title: "Смотрите также", items: details.related)
                }

                if details.commentsCount > 0 || !model.comments.isEmpty {
                    comments(details)
                }
            }
            .padding(.vertical, 50)
        }
    }

    /// True once the main play button exists (for series it waits for the episode list).
    private var isPlayReady: Bool {
        guard let details = model.details else { return false }
        return !details.isSeries || model.resumeEpisode(progress: progress) != nil
    }

    private func metaLine(_ details: MediaDetails) -> some View {
        let parts = [
            details.info("Дата выхода") ?? details.info("Год"),
            details.info("Страна"),
            details.info("Жанр"),
            details.info("Время"),
            details.info("Возраст"),
        ].compactMap { $0 }
        return Text(parts.joined(separator: "  ·  "))
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    // MARK: Actions

    @ViewBuilder
    private func actions(_ details: MediaDetails) -> some View {
        HStack(spacing: 30) {
            if details.isSeries {
                if let target = model.resumeEpisode(progress: progress) {
                    let season = model.seasons.first { $0.id == target.episode.seasonId }?.title ?? ""
                    Button {
                        model.play(episode: target.episode)
                    } label: {
                        Label(target.entry == nil ? "Смотреть: \(season), \(target.episode.title)" : "Продолжить: \(season), \(target.episode.title)",
                              systemImage: "play.fill")
                    }
                    .focused($isPlayFocused)
                } else if model.isLoadingEpisodes {
                    ProgressView()
                }
            } else {
                let entry = progress.entry(postId: details.postId, seasonId: nil, episodeId: nil)
                if let entry, !entry.isFinished, entry.position > 30 {
                    Button {
                        model.play()
                    } label: {
                        Label("Продолжить с \(entry.position.playbackTime)", systemImage: "play.fill")
                    }
                    .focused($isPlayFocused)
                    Button {
                        model.play(from: 0)
                    } label: {
                        Label("Сначала", systemImage: "backward.end.fill")
                    }
                } else {
                    Button {
                        model.play(from: 0)
                    } label: {
                        Label("Смотреть", systemImage: "play.fill")
                    }
                    .focused($isPlayFocused)
                }
            }

            if details.translators.count > 1 {
                Menu {
                    ForEach(details.translators) { translator in
                        Button {
                            Task { await model.select(translator) }
                        } label: {
                            let title = translator.isPremium ? "\(translator.name) · Premium" : translator.name
                            if translator == model.translator {
                                Label(title, systemImage: "checkmark")
                            } else if translator.isPremium {
                                Label(title, systemImage: "crown.fill")
                            } else {
                                Text(title)
                            }
                        }
                    }
                } label: {
                    Label(model.translator?.name ?? "Озвучка", systemImage: model.translator?.isPremium == true ? "crown.fill" : "waveform")
                        .lineLimit(1)
                }
            } else if let translator = model.translator {
                Label(translator.name, systemImage: "waveform")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let folders = model.bookmarkFolders {
                bookmarkMenu(folders)
            }
        }
    }

    /// Folders with a checkmark where the title is; picking one adds or removes it there.
    private func bookmarkMenu(_ folders: [BookmarkFolder]) -> some View {
        Menu {
            ForEach(folders) { folder in
                Button {
                    Task { await model.toggleBookmark(in: folder) }
                } label: {
                    if model.bookmarkedIn.contains(folder.id) {
                        Label(folder.name, systemImage: "checkmark")
                    } else {
                        Text(folder.name)
                    }
                }
            }
            Button {
                newFolderName = ""
                isCreatingFolder = true
            } label: {
                Label("Новая папка…", systemImage: "folder.badge.plus")
            }
        } label: {
            Label(model.bookmarkedIn.isEmpty ? "В закладки" : "В закладках",
                  systemImage: model.bookmarkedIn.isEmpty ? "bookmark" : "bookmark.fill")
                .lineLimit(1)
        }
    }

    // MARK: Comments

    private func comments(_ details: MediaDetails) -> some View {
        VStack(alignment: .leading, spacing: 30) {
            Text("Отзывы (\(max(details.commentsCount, model.comments.count)))")
                .font(.title3.bold())

            // Not lazy: below the fold a lazy stack has no cards yet, so focus could not move down into it.
            VStack(alignment: .leading, spacing: 28) {
                ForEach(model.comments) { comment in
                    CommentCard(comment: comment, isRevealed: revealedSpoilers.contains(comment.id)) {
                        guard comment.hasSpoiler else { return }
                        if revealedSpoilers.contains(comment.id) {
                            revealedSpoilers.remove(comment.id)
                        } else {
                            revealedSpoilers.insert(comment.id)
                        }
                    }
                }
            }

            if let error = model.commentsError {
                Text(error.localizedDescription)
                    .foregroundStyle(.secondary)
            }
            if model.commentsError != nil || model.hasMoreComments {
                // Stays on screen while loading so focus does not jump away from it.
                Button {
                    Task { await model.loadMoreComments() }
                } label: {
                    HStack(spacing: 16) {
                        if model.isLoadingComments { ProgressView() }
                        Text(model.commentsError != nil ? "Повторить" : "Показать ещё отзывы")
                    }
                }
            } else if model.isLoadingComments {
                ProgressView()
            }
        }
        .padding(.horizontal, 80)
        .focusSection()
    }

    // MARK: Episodes

    private func episodes(_ details: MediaDetails) -> some View {
        VStack(alignment: .leading, spacing: 30) {
            if model.seasons.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 20) {
                        ForEach(model.seasons) { season in
                            Button {
                                model.selectedSeasonId = season.id
                            } label: {
                                HStack(spacing: 10) {
                                    if season.id == model.selectedSeason?.id {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(season.title)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 16)
                }
                .scrollClipDisabled()
                .focusSection()
            } else if let season = model.selectedSeason {
                Text(season.title)
                    .font(.title3.bold())
                    .padding(.horizontal, 80)
            }

            if model.isLoadingEpisodes {
                ProgressView().padding(.horizontal, 80)
            } else if let error = model.episodesError {
                Text(error.localizedDescription)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 80)
            } else if let season = model.selectedSeason {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 36) {
                        ForEach(season.episodes) { episode in
                            EpisodeCard(
                                episode: episode,
                                entry: progress.entry(postId: details.postId, seasonId: episode.seasonId, episodeId: episode.id)
                            ) {
                                model.play(episode: episode)
                            }
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 20)
                }
                .scrollClipDisabled()
                .focusSection()
            }
        }
    }
}

/// A comment as a focusable card, so the list scrolls with the remote; pressing it shows a hidden spoiler.
private struct CommentCard: View {
    let comment: Comment
    let isRevealed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(comment.author)
                        .font(.headline)
                        .lineLimit(1)
                    Text(comment.date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if comment.likes > 0 {
                        Label("\(comment.likes)", systemImage: "hand.thumbsup.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if comment.hasSpoiler {
                    Text(isRevealed ? "Нажмите, чтобы скрыть спойлер" : "Спойлер скрыт — нажмите, чтобы показать")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
        }
        .buttonStyle(.card)
        // Long lines are hard to read across a TV; replies step in under their parent.
        .frame(maxWidth: 1400, alignment: .leading)
        .padding(.leading, CGFloat(min(comment.depth, 4)) * 60)
    }

    private var text: AttributedString {
        var result = AttributedString()
        for part in comment.parts {
            var piece = AttributedString(part.isSpoiler && !isRevealed ? "[спойлер]" : part.text)
            if part.isSpoiler { piece.foregroundColor = .orange }
            result += piece
        }
        return result
    }
}

private struct EpisodeCard: View {
    let episode: Episode
    let entry: WatchProgressStore.Entry?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(white: 0.24), Color(white: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(episode.title)
                            .font(.headline)
                            .lineLimit(2)
                        Spacer()
                        if entry?.isFinished == true {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    if let entry, !entry.isFinished {
                        ProgressView(value: entry.fraction)
                            .tint(.accentColor)
                    }
                }
                .padding(20)
            }
            .frame(width: 320, height: 180)
        }
        .buttonStyle(.card)
    }
}
