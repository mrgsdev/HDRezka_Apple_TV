import Foundation

enum MediaKind: String, Codable, Hashable {
    case film, series, cartoon, anime, unknown

    init(cssClasses: [String]) {
        if cssClasses.contains("films") { self = .film }
        else if cssClasses.contains("series") { self = .series }
        else if cssClasses.contains("cartoons") { self = .cartoon }
        else if cssClasses.contains("animation") { self = .anime }
        else { self = .unknown }
    }

    var title: String? {
        switch self {
        case .film: "Фильм"
        case .series: "Сериал"
        case .cartoon: "Мультфильм"
        case .anime: "Аниме"
        case .unknown: nil
        }
    }
}

/// An item of any listing (catalog, search, bookmarks, continue watching).
struct MediaItem: Identifiable, Hashable, Codable {
    /// Site-relative path of the details page, e.g. `/films/drama/12345-name-2020.html`.
    let path: String
    let title: String
    let subtitle: String
    let posterURL: URL?
    let kind: MediaKind
    /// Short badge from the cover, e.g. "2 сезон, 8 серия".
    let badge: String?
    /// Id of the entry in the site's "continue watching" list, used to remove it.
    var continueId: String? = nil

    var id: String { path }
}

struct Page<T> {
    let items: [T]
    let hasMore: Bool
}

struct Translator: Identifiable, Hashable {
    let id: String
    let name: String
    var isCamrip = "0"
    var isAds = "0"
    var isDirector = "0"
    var isPremium = false
}

struct Episode: Identifiable, Hashable {
    let id: String
    let seasonId: String
    let title: String
}

struct Season: Identifiable, Hashable {
    let id: String
    let title: String
    let episodes: [Episode]
}

struct InfoRow: Hashable {
    let title: String
    let value: String
}

struct MediaDetails {
    let postId: String
    let path: String
    let title: String
    let originalTitle: String
    let posterURL: URL?
    let description: String
    let info: [InfoRow]
    let favs: String
    let isSeries: Bool
    let translators: [Translator]
    let activeTranslatorId: String?
    /// Seasons embedded in the page for the active translator.
    let seasons: [Season]
    let related: [MediaItem]
    /// The account's bookmark folders; nil when the page offers no bookmarks (logged out).
    let bookmarkFolders: [BookmarkFolder]?
    /// Ids of the folders that hold this title.
    let bookmarkedIn: Set<String>
    /// "Отзывы (N)" on the page; the comments themselves load separately.
    let commentsCount: Int

    func info(_ title: String) -> String? {
        info.first { $0.title.hasPrefix(title) }?.value
    }
}

struct StreamQuality: Identifiable, Hashable {
    let label: String
    let url: URL
    let fallbackURL: URL?
    /// Premium-only quality: without HDrezka Premium the site serves a ~1 minute teaser instead.
    var isPremium = false

    var id: String { label }

    /// Higher is better; used to pick the default quality.
    var rank: Int {
        let digits = Int(label.prefix { $0.isNumber }) ?? 0
        return digits * 10 + (label.localizedCaseInsensitiveContains("ultra") ? 5 : 0)
    }
}

struct SubtitleTrack: Identifiable, Hashable {
    let label: String
    let url: URL
    let language: String?

    var id: String { label }
}

struct StreamInfo {
    let qualities: [StreamQuality]
    let subtitles: [SubtitleTrack]
    let defaultSubtitle: String?
}

/// A comment under a title. The site's reply tree is flattened in reading order, with `depth` for indentation.
struct Comment: Identifiable, Hashable {
    struct Part: Hashable {
        let text: String
        /// Hidden behind "спойлер" until the viewer asks to see it.
        let isSpoiler: Bool
    }

    let id: String
    let author: String
    let date: String
    let parts: [Part]
    let likes: Int
    /// 0 for a comment on the title, 1 and more for replies.
    let depth: Int

    var hasSpoiler: Bool { parts.contains(where: \.isSpoiler) }
}

struct BookmarkFolder: Identifiable, Hashable {
    let id: String
    let name: String
    let count: Int?
}
