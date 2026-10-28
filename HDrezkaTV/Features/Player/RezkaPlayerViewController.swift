import AVKit
import UIKit

struct PlaybackRequest {
    let postId: String
    let title: String
    let posterURL: URL?
    let favs: String
    let translator: Translator
    /// All seasons for this translator; used for "next episode".
    let seasons: [Season]
    var seasonId: String?
    var episodeId: String?
    /// nil resumes from the saved position, 0 starts over.
    var startPosition: Double?
}

enum PlayerPresenter {
    @MainActor
    static func present(_ request: PlaybackRequest) {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        top.present(RezkaPlayerViewController(request: request), animated: true)
    }
}

/// Full-screen player: system transport bar plus quality/subtitle menus and a WebVTT overlay
/// (HDrezka serves subtitles as separate files that AVPlayer cannot attach to an MP4 by itself).
final class RezkaPlayerViewController: AVPlayerViewController {
    private var request: PlaybackRequest
    private var stream: StreamInfo?
    private var quality: StreamQuality?
    private var subtitle: SubtitleTrack?
    private var cues: [SubtitleCue] = []
    /// Kept for the whole player session, across quality switches and episodes.
    private var speed: Float = 1

    private static let speedOptions: [Float] = [1, 1.25, 1.5, 1.75, 2]

    private let subtitleLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var loadTask: Task<Void, Never>?
    private var subtitleTask: Task<Void, Never>?
    private var remoteSaveTask: Task<Void, Never>?

    private var pendingSeek: Double?
    private var usingFallback = false
    private var lastLocalSave = Date.distantPast
    private var lastRemoteSave = Date()
    private var isTornDown = false

    init(request: PlaybackRequest) {
        self.request = request
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        player = AVPlayer()
        // The "Скорость" menu replaces the system speed control so all options sit side by side.
        speeds = []
        setUpOverlay()
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        load(startAt: request.startPosition)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed || presentingViewController == nil { finish() }
    }

    // MARK: Loading

    private func load(startAt: Double?) {
        loadTask?.cancel()
        spinner.startAnimating()
        cues = []
        subtitleLabel.attributedText = nil
        rebuildMenus()

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await RezkaClient.shared.stream(
                    postId: request.postId,
                    translator: request.translator,
                    seasonId: request.seasonId,
                    episodeId: request.episodeId,
                    favs: request.favs
                )
                try Task.checkCancellation()
                guard let quality = QualityPreference.pick(from: stream.qualities, allowPremium: AuthSession.shared.isPremium) else {
                    throw RezkaError.noStreams
                }
                self.stream = stream
                play(quality, at: startAt ?? savedPosition())
                restoreSubtitle()
                rebuildMenus()
            } catch is CancellationError {
            } catch {
                spinner.stopAnimating()
                AuthSession.shared.handle(error)
                showError(error)
            }
        }
    }

    private func play(_ quality: StreamQuality, at position: Double, fallback: Bool = false) {
        self.quality = quality
        usingFallback = fallback
        pendingSeek = position > 1 ? position : nil

        let item = AVPlayerItem(url: fallback ? (quality.fallbackURL ?? quality.url) : quality.url)
        item.externalMetadata = metadata()
        observe(item)
        player?.replaceCurrentItem(with: item)
        player?.play()
        loadArtwork(for: item)
    }

    private func observe(_ item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async { self?.statusChanged(item) }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.itemDidFinish() }
        }
    }

    private func statusChanged(_ item: AVPlayerItem) {
        guard item === player?.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            spinner.stopAnimating()
            if let pendingSeek {
                self.pendingSeek = nil
                player?.seek(to: CMTime(seconds: pendingSeek, preferredTimescale: 600))
            }
        case .failed:
            if !usingFallback, let quality, quality.fallbackURL != nil {
                play(quality, at: pendingSeek ?? currentPosition, fallback: true)
            } else {
                spinner.stopAnimating()
                showError(item.error ?? RezkaError.noStreams)
            }
        default:
            break
        }
    }

    private func itemDidFinish() {
        guard !isPreviewClip else {
            // A premium-quality teaser ended: keep the episode unwatched and stay on it.
            dismiss(animated: true)
            return
        }
        recordProgress(force: true, finished: true)
        if nextEpisode() != nil {
            playNext()
        } else {
            dismiss(animated: true)
        }
    }

    // MARK: Menus

    private func rebuildMenus() {
        var items: [UIMenuElement] = []

        if let stream {
            let qualities = stream.qualities.sorted { $0.rank > $1.rank }.map { option in
                UIAction(title: option.isPremium ? "\(option.label) ★ Premium" : option.label, state: option == quality ? .on : .off) { [weak self] _ in
                    self?.switchQuality(option)
                }
            }
            items.append(UIMenu(title: "Качество", image: UIImage(systemName: "slider.horizontal.3"), options: .singleSelection, children: qualities))

            if !stream.subtitles.isEmpty {
                var tracks = [UIAction(title: "Выключены", state: subtitle == nil ? .on : .off) { [weak self] _ in
                    self?.selectSubtitle(nil)
                }]
                tracks += stream.subtitles.map { track in
                    UIAction(title: track.label, state: track == subtitle ? .on : .off) { [weak self] _ in
                        self?.selectSubtitle(track)
                    }
                }
                items.append(UIMenu(title: "Субтитры", image: UIImage(systemName: "captions.bubble"), options: .singleSelection, children: tracks))
            }
        }

        let speeds = Self.speedOptions.map { rate in
            UIAction(title: Self.speedLabel(rate), state: rate == speed ? .on : .off) { [weak self] _ in
                self?.setSpeed(rate)
            }
        }
        items.append(UIMenu(title: "Скорость", image: UIImage(systemName: "gauge.with.dots.needle.67percent"), options: .singleSelection, children: speeds))

        if nextEpisode() != nil {
            items.append(UIAction(title: "Следующая серия", image: UIImage(systemName: "forward.end")) { [weak self] _ in
                self?.playNext()
            })
        }

        transportBarCustomMenuItems = items
    }

    private func switchQuality(_ option: StreamQuality) {
        guard option != quality else { return }
        QualityPreference.current = option.label
        play(option, at: currentPosition)
        rebuildMenus()
    }

    /// `defaultRate` is what `play()` resumes at, so the speed survives pausing and the next episode.
    private func setSpeed(_ rate: Float) {
        speed = rate
        player?.defaultRate = rate
        if let player, player.rate != 0 { player.rate = rate }
        rebuildMenus()
    }

    private static func speedLabel(_ rate: Float) -> String {
        rate == 1 ? "Обычная" : rate.formatted(.number.locale(Locale(identifier: "ru_RU"))) + "×"
    }

    // MARK: Subtitles

    private func restoreSubtitle() {
        let track = SubtitlePreference.current.flatMap { label in stream?.subtitles.first { $0.label == label } }
        selectSubtitle(track, remember: false)
    }

    private func selectSubtitle(_ track: SubtitleTrack?, remember: Bool = true) {
        subtitle = track
        cues = []
        subtitleLabel.attributedText = nil
        if remember { SubtitlePreference.current = track?.label }
        rebuildMenus()

        subtitleTask?.cancel()
        guard let track else { return }
        subtitleTask = Task { [weak self] in
            guard let text = try? await RezkaClient.shared.downloadText(track.url) else { return }
            let cues = WebVTT.parse(text)
            guard let self, !Task.isCancelled, subtitle == track else { return }
            self.cues = cues
        }
    }

    private func setUpOverlay() {
        guard let overlay = contentOverlayView else { return }

        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(subtitleLabel)

        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(spinner)

        NSLayoutConstraint.activate([
            subtitleLabel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 160),
            subtitleLabel.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -90),
            spinner.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
        ])
    }

    private func showSubtitle(_ text: String?) {
        guard let text else {
            subtitleLabel.attributedText = nil
            return
        }
        guard subtitleLabel.attributedText?.string != text else { return }
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = CGSize(width: 0, height: 2)
        subtitleLabel.attributedText = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 48, weight: .semibold),
            .foregroundColor: UIColor.white,
            .strokeColor: UIColor.black,
            .strokeWidth: -2.5,
            .shadow: shadow,
        ])
    }

    // MARK: Progress

    private var currentPosition: Double {
        let seconds = player?.currentTime().seconds ?? 0
        return seconds.isFinite ? seconds : 0
    }

    private var currentDuration: Double {
        let seconds = player?.currentItem?.duration.seconds ?? 0
        return seconds.isFinite ? seconds : 0
    }

    private func tick(_ time: Double) {
        if !cues.isEmpty { showSubtitle(WebVTT.text(at: time, in: cues)) }
        if Date().timeIntervalSince(lastLocalSave) > 5 { recordProgress() }
    }

    private func savedPosition() -> Double {
        guard let entry = WatchProgressStore.shared.entry(postId: request.postId, seasonId: request.seasonId, episodeId: request.episodeId),
              !entry.isFinished, entry.position > 15 else { return 0 }
        return max(entry.position - 3, 0)
    }

    /// Clips under 3 minutes are teasers (e.g. premium quality on a free account), not the episode.
    private var isPreviewClip: Bool {
        currentDuration > 0 && currentDuration < 180
    }

    private func recordProgress(force: Bool = false, finished: Bool = false) {
        let duration = currentDuration
        guard duration > 0, pendingSeek == nil, !isPreviewClip else { return }
        let position = finished ? duration : currentPosition
        guard position > 0 else { return }
        lastLocalSave = Date()

        WatchProgressStore.shared.update(.init(
            postId: request.postId,
            translatorId: request.translator.id,
            seasonId: request.seasonId,
            episodeId: request.episodeId,
            position: position,
            duration: duration,
            updatedAt: Date()
        ), persistNow: force)

        if force || Date().timeIntervalSince(lastRemoteSave) > 60 {
            lastRemoteSave = Date()
            let request = request
            remoteSaveTask = Task {
                await RezkaClient.shared.saveProgress(
                    postId: request.postId,
                    translatorId: request.translator.id,
                    seasonId: request.seasonId,
                    episodeId: request.episodeId,
                    position: position,
                    duration: duration
                )
            }
        }
    }

    // MARK: Episodes

    private func nextEpisode() -> Episode? {
        guard let seasonId = request.seasonId, let episodeId = request.episodeId else { return nil }
        let all = request.seasons.flatMap(\.episodes)
        guard let index = all.firstIndex(where: { $0.seasonId == seasonId && $0.id == episodeId }), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    private func playNext() {
        guard let next = nextEpisode() else { return }
        recordProgress(force: true)
        request.seasonId = next.seasonId
        request.episodeId = next.id
        player?.pause()
        load(startAt: nil)
    }

    // MARK: Metadata & errors

    private var episodeLabel: String? {
        guard let seasonId = request.seasonId, let episodeId = request.episodeId else { return nil }
        let season = request.seasons.first { $0.id == seasonId }
        let episode = season?.episodes.first { $0.id == episodeId }
        return [season?.title ?? "Сезон \(seasonId)", episode?.title ?? "Серия \(episodeId)", request.translator.name].joined(separator: " · ")
    }

    private func metadata() -> [AVMetadataItem] {
        var items = [metadataItem(.commonIdentifierTitle, request.title as NSString)]
        items.append(metadataItem(.iTunesMetadataTrackSubTitle, (episodeLabel ?? request.translator.name) as NSString))
        return items
    }

    private func metadataItem(_ identifier: AVMetadataIdentifier, _ value: NSCopying & NSObjectProtocol) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }

    private func loadArtwork(for item: AVPlayerItem) {
        guard let url = request.posterURL else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url), let self, item === player?.currentItem else { return }
            let artwork = metadataItem(.commonIdentifierArtwork, data as NSData)
            item.externalMetadata.append(artwork)
        }
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: "Не удалось воспроизвести", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    private func finish() {
        guard !isTornDown else { return }
        isTornDown = true
        recordProgress(force: true)
        // Once the final position reaches the site, let "continue watching" refresh.
        let save = remoteSaveTask
        Task {
            await save?.value
            NotificationCenter.default.post(name: .watchHistoryChanged, object: nil)
        }
        loadTask?.cancel()
        subtitleTask?.cancel()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        statusObservation = nil
        player?.pause()
    }
}
