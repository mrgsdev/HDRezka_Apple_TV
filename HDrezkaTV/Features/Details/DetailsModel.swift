import Foundation
import Observation

@MainActor
@Observable
final class DetailsModel {
    enum State {
        case loading
        case loaded(MediaDetails)
        case failed(Error)
    }

    let item: MediaItem
    private(set) var state: State = .loading
    private(set) var translator: Translator?
    private(set) var seasons: [Season] = []
    var selectedSeasonId: String?
    private(set) var isLoadingEpisodes = false
    private(set) var episodesError: Error?

    init(item: MediaItem) {
        self.item = item
    }

    var details: MediaDetails? {
        if case let .loaded(details) = state { details } else { nil }
    }

    var selectedSeason: Season? {
        seasons.first { $0.id == selectedSeasonId } ?? seasons.first
    }

    func loadIfNeeded() async {
        if details == nil { await load() }
    }

    func load() async {
        state = .loading
        do {
            let details = try await RezkaClient.shared.details(path: item.path)
            let last = WatchProgressStore.shared.last(postId: details.postId)
            // Without Premium, premium dubs play only a teaser, so default to a free one.
            let playable = AuthSession.shared.isPremium ? details.translators : details.translators.filter { !$0.isPremium }
            let pool = playable.isEmpty ? details.translators : playable
            let chosen = pool.first { $0.id == last?.translatorId }
                ?? pool.first { $0.id == details.activeTranslatorId }
                ?? pool.first
            translator = chosen
            state = .loaded(details)

            guard details.isSeries, let chosen else { return }
            if chosen.id == details.activeTranslatorId, !details.seasons.isEmpty {
                apply(details.seasons, postId: details.postId)
            } else {
                await loadSeasons(details, chosen)
            }
        } catch where !error.isCancellation {
            state = .failed(error)
            AuthSession.shared.handle(error)
        } catch {}
    }

    func select(_ translator: Translator) async {
        guard let details, translator != self.translator else { return }
        self.translator = translator
        if details.isSeries { await loadSeasons(details, translator) }
    }

    private func loadSeasons(_ details: MediaDetails, _ translator: Translator) async {
        isLoadingEpisodes = true
        episodesError = nil
        do {
            let seasons = try await RezkaClient.shared.seasons(postId: details.postId, translatorId: translator.id, favs: details.favs)
            guard translator == self.translator else { return }
            apply(seasons, postId: details.postId)
        } catch where !error.isCancellation {
            episodesError = error
            AuthSession.shared.handle(error)
        } catch {}
        isLoadingEpisodes = false
    }

    private func apply(_ seasons: [Season], postId: String) {
        self.seasons = seasons
        let lastSeason = WatchProgressStore.shared.last(postId: postId)?.seasonId
        selectedSeasonId = seasons.first { $0.id == lastSeason }?.id ?? seasons.first?.id
    }

    // MARK: Playback

    /// The episode the main button should play: the next unfinished one after the last watched.
    func resumeEpisode(progress: WatchProgressStore) -> (episode: Episode, entry: WatchProgressStore.Entry?)? {
        guard let details else { return nil }
        let all = seasons.flatMap(\.episodes)
        guard let first = all.first else { return nil }
        guard let last = progress.last(postId: details.postId),
              let index = all.firstIndex(where: { $0.seasonId == last.seasonId && $0.id == last.episodeId })
        else { return (first, nil) }
        if last.isFinished, index + 1 < all.count {
            return (all[index + 1], nil)
        }
        return (all[index], last)
    }

    func play(episode: Episode? = nil, from position: Double? = nil) {
        guard let details, let translator else { return }
        PlayerPresenter.present(PlaybackRequest(
            postId: details.postId,
            title: details.title,
            posterURL: details.posterURL ?? item.posterURL,
            favs: details.favs,
            translator: translator,
            seasons: seasons,
            seasonId: episode?.seasonId,
            episodeId: episode?.id,
            startPosition: position
        ))
    }
}
