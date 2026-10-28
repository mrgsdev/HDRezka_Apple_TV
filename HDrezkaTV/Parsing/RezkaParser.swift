import Foundation
import SwiftSoup

/// Turns HDrezka HTML into models. All selectors live here so layout changes are fixed in one place.
enum RezkaParser {
    // MARK: Listings

    static func items(in root: Element, base: URL) throws -> [MediaItem] {
        try root.select(".b-content__inline_item").array().compactMap { try item(from: $0, base: base) }
    }

    static func page(in doc: Document, base: URL) throws -> Page<MediaItem> {
        let container = try doc.select(".b-content__inline_items").first() ?? doc
        let items = try items(in: container, base: base)
        let next = try doc.select(".b-navigation__next").first()
        let hasMore = next?.parent()?.tagName() == "a"
        return Page(items: items, hasMore: hasMore && !items.isEmpty)
    }

    private static func item(from element: Element, base: URL) throws -> MediaItem? {
        let link = try element.select(".b-content__inline_item-link a").first()
        let href = try element.attr("data-url").nonEmpty ?? link?.attr("href") ?? ""
        guard let path = sitePath(href, base: base) else { return nil }

        let cover = try element.select(".b-content__inline_item-cover").first()
        let classes = try cover?.select(".cat").first()?.className().split(separator: " ").map(String.init) ?? []
        let poster = try cover?.select("img").first()?.attr("src")

        return MediaItem(
            path: path,
            title: try link?.text() ?? "",
            subtitle: try element.select(".b-content__inline_item-link div").first()?.text() ?? "",
            posterURL: absoluteURL(poster, base: base),
            kind: MediaKind(cssClasses: classes),
            badge: try cover?.select(".info").first()?.text().nonEmpty
        )
    }

    // MARK: Continue watching

    static func continueWatching(in doc: Document, base: URL) throws -> [MediaItem] {
        try doc.select(".b-videosaves__list_item[id^=videosave]").array().compactMap { row in
            guard let link = try row.select(".td.title a").first(),
                  let path = sitePath(try link.attr("href"), base: base) else { return nil }
            let info = try row.select(".td.info").first()?.text() ?? ""
            let year = try row.select(".td.title small").first()?.text() ?? ""
            let removeId = try row.select(".i-sprt.delete").first()?.attr("data-id").nonEmpty
                ?? row.id().components(separatedBy: "-").last?.nonEmpty
            return MediaItem(
                path: path,
                title: try link.text(),
                subtitle: info.isEmpty ? year : info,
                posterURL: absoluteURL(try link.attr("data-cover_url"), base: base),
                kind: .unknown,
                badge: nil,
                continueId: removeId
            )
        }
    }

    // MARK: Bookmarks

    static func bookmarkFolders(in doc: Document) throws -> [BookmarkFolder] {
        try doc.select(".b-favorites_content__cats_list_item").array().compactMap { element in
            let id = try element.attr("data-cat_id")
            guard !id.isEmpty else { return nil }
            let name = try element.select(".name").first()?.text() ?? element.text()
            let count = try Int(element.select(".num-holder").first()?.text().filter(\.isNumber) ?? "")
            return BookmarkFolder(id: id, name: name, count: count)
        }
    }

    // MARK: Details

    static func details(in doc: Document, path: String, base: URL) throws -> MediaDetails {
        let html = try doc.html()
        let seriesArgs = initArguments(in: html, function: "initCDNSeriesEvents")
        let movieArgs = initArguments(in: html, function: "initCDNMoviesEvents")

        let postId = try [
            doc.select("#post_id").first()?.attr("value"),
            doc.select("[data-post_id]").first()?.attr("data-post_id"),
            (seriesArgs ?? movieArgs)?.first,
            idFromPath(path),
        ].compactMap { $0?.nonEmpty }.first
        guard let postId else { throw RezkaError.parsing("post id") }

        let info = try infoRows(in: doc)
        let hasEpisodeTabs = try !doc.select("#simple-episodes-tabs").isEmpty()
        let isSeries = seriesArgs != nil || hasEpisodeTabs

        var translators = try doc.select("#translators-list .b-translator__item").array().map { element in
            var name = try element.attr("title").nonEmpty ?? element.text()
            if let flag = try element.select("img").first()?.attr("title").nonEmpty ?? element.select("img").first()?.attr("alt").nonEmpty,
               !name.localizedCaseInsensitiveContains(flag) {
                name += " (\(flag))"
            }
            return Translator(
                id: try element.attr("data-translator_id"),
                name: name,
                isCamrip: try element.attr("data-camrip").nonEmpty ?? "0",
                isAds: try element.attr("data-ads").nonEmpty ?? "0",
                isDirector: try element.attr("data-director").nonEmpty ?? "0",
                isPremium: element.hasClass("b-prem_translator")
            )
        }.filter { !$0.id.isEmpty }

        let activeTranslatorId = try doc.select("#translators-list .b-translator__item.active").first()?.attr("data-translator_id").nonEmpty
            ?? (seriesArgs ?? movieArgs).flatMap { $0.count > 1 ? $0[1] : nil }

        if translators.isEmpty, let id = activeTranslatorId {
            let name = info.first { $0.title.hasPrefix("В переводе") }?.value ?? "По умолчанию"
            var single = Translator(id: id, name: name)
            if let args = movieArgs, args.count >= 5 {
                single.isCamrip = args[2]
                single.isAds = args[3]
                single.isDirector = args[4]
            }
            translators = [single]
        }

        let bookmarks = try bookmarkFolders(onDetails: doc)
        let posterHref = try doc.select(".b-sidecover a").first()?.attr("href")
        let posterSrc = try doc.select(".b-sidecover img").first()?.attr("src")

        return MediaDetails(
            postId: postId,
            path: path,
            title: try doc.select(".b-post__title h1").first()?.text().nonEmpty ?? doc.select(".b-post__title").text(),
            originalTitle: try doc.select(".b-post__origtitle").first()?.text() ?? "",
            posterURL: absoluteURL(posterHref?.hasImageExtension == true ? posterHref : posterSrc, base: base),
            description: try doc.select(".b-post__description_text").first()?.text() ?? "",
            info: info,
            favs: try doc.select("#ctrl_favs").first()?.attr("value") ?? "",
            isSeries: isSeries,
            translators: translators,
            activeTranslatorId: activeTranslatorId,
            seasons: isSeries ? try seasons(in: doc) : [],
            related: try doc.select(".b-sidelist").first().map { try items(in: $0, base: base) } ?? [],
            bookmarkFolders: bookmarks?.folders,
            bookmarkedIn: bookmarks?.checked ?? []
        )
    }

    /// The account's bookmark folders from a details page and those holding the title;
    /// nil when the page has no bookmark controls (logged out).
    private static func bookmarkFolders(onDetails doc: Document) throws -> (folders: [BookmarkFolder], checked: Set<String>)? {
        guard try doc.select("#user-favorites-holder").first() != nil else { return nil }
        var folders: [BookmarkFolder] = []
        var checked = Set<String>()
        for row in try doc.select("#user-favorites-list .hd-label-row").array() {
            guard let input = try row.select("input").first() else { continue }
            let id = try input.attr("value")
            guard !id.isEmpty else { continue }
            let label = try row.select("label").first()
            let name = try label?.ownText().nonEmpty ?? label?.text() ?? id
            let count = try Int(row.select("small b").first()?.text() ?? "")
            folders.append(BookmarkFolder(id: id, name: name, count: count))
            if input.hasAttr("checked") { checked.insert(id) }
        }
        return (folders, checked)
    }

    static func seasons(in root: Element) throws -> [Season] {
        var order: [String] = []
        var episodesBySeason: [String: [Episode]] = [:]
        for element in try root.select(".b-simple_episode__item").array() {
            let seasonId = try element.attr("data-season_id")
            let episodeId = try element.attr("data-episode_id")
            guard !seasonId.isEmpty, !episodeId.isEmpty else { continue }
            if episodesBySeason[seasonId] == nil { order.append(seasonId) }
            let title = try element.text().nonEmpty ?? "Серия \(episodeId)"
            episodesBySeason[seasonId, default: []].append(Episode(id: episodeId, seasonId: seasonId, title: title))
        }

        var titles: [String: String] = [:]
        var seasonOrder: [String] = []
        for element in try root.select(".b-simple_season__item").array() {
            let id = try element.attr("data-tab_id")
            guard !id.isEmpty else { continue }
            titles[id] = try element.text()
            seasonOrder.append(id)
        }
        if seasonOrder.isEmpty { seasonOrder = order }

        return seasonOrder.compactMap { id in
            guard let episodes = episodesBySeason[id], !episodes.isEmpty else { return nil }
            return Season(id: id, title: titles[id] ?? "Сезон \(id)", episodes: episodes)
        }
    }

    private static func infoRows(in doc: Document) throws -> [InfoRow] {
        var rows: [InfoRow] = []
        for row in try doc.select(".b-post__info tr").array() {
            let cells = try row.select("td")
            if cells.size() == 2 {
                let title = try cells.get(0).text().trimmingCharacters(in: CharacterSet(charactersIn: ": "))
                let value = try cells.get(1).text()
                if !title.isEmpty, !value.isEmpty { rows.append(InfoRow(title: title, value: value)) }
            } else if let holder = try row.select(".persons-list-holder").first() {
                let names = try holder.select(".person-name-item").array().map { try $0.text() }.filter { !$0.isEmpty }
                if !names.isEmpty {
                    rows.append(InfoRow(title: "В ролях", value: names.prefix(12).joined(separator: ", ")))
                }
            }
        }
        return rows
    }

    /// Arguments of `sof.tv.initCDNSeriesEvents(postId, translatorId, ...)` up to the JSON config.
    static func initArguments(in html: String, function: String) -> [String]? {
        guard let start = html.range(of: function + "(") else { return nil }
        let tail = html[start.upperBound...].prefix { $0 != "{" && $0 != ")" }
        let args = tail.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        }
        return args.isEmpty ? nil : args
    }

    // MARK: Helpers

    static func sitePath(_ href: String, base: URL) -> String? {
        guard !href.isEmpty, let url = URL(string: href, relativeTo: base) else { return nil }
        let path = url.path
        return path.isEmpty || path == "/" ? nil : path
    }

    static func absoluteURL(_ string: String?, base: URL) -> URL? {
        guard let string = string?.nonEmpty else { return nil }
        if string.hasPrefix("//") { return URL(string: "https:" + string) }
        return URL(string: string, relativeTo: base)?.absoluteURL
    }

    /// `/films/drama/12345-name-2020.html` → `12345`, the site's post id.
    static func idFromPath(_ path: String) -> String? {
        let last = path.split(separator: "/").last ?? ""
        let digits = last.prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }
}

extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    fileprivate var hasImageExtension: Bool {
        let lower = lowercased()
        return [".jpg", ".jpeg", ".png", ".webp"].contains { lower.hasSuffix($0) }
    }
}
