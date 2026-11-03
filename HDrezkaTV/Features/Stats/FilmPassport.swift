import Foundation

/// Countries stamped in the film passport: where the titles watched in REZKA come from.
@MainActor
enum FilmPassport {
    /// Titles watched at least ten minutes count; a country's day is the first day any of them played.
    static func stamps(from stats: WatchStats) -> [PassportStamp] {
        var total: [String: Double] = [:]
        var first: [String: String] = [:]
        for (day, titles) in stats.days {
            for (postId, seconds) in titles {
                total[postId, default: 0] += seconds
                if first[postId].map({ day < $0 }) ?? true { first[postId] = day }
            }
        }
        var byCountry: [String: (day: String, titles: Int)] = [:]
        for (postId, seconds) in total where seconds >= 600 {
            guard let day = first[postId], let countries = stats.titles[postId]?.countries else { continue }
            for country in countries {
                let current = byCountry[country]
                byCountry[country] = (min(current?.day ?? day, day), (current?.titles ?? 0) + 1)
            }
        }
        return byCountry.compactMap { country, value in
            WatchStats.date(ofDay: value.day).map { PassportStamp(country: country, firstDay: $0, titles: value.titles) }
        }
        .sorted { $0.firstDay != $1.firstDay ? $0.firstDay > $1.firstDay : $0.country < $1.country }
    }
}

struct PassportStamp: Identifiable {
    enum Level {
        case stamp, visa, residence
    }

    /// Titles from a country for a gold visa and for a residence permit.
    static let visaAt = 5
    static let residenceAt = 20

    let country: String
    let firstDay: Date
    let titles: Int

    var id: String { country }

    var level: Level {
        titles >= Self.residenceAt ? .residence : titles >= Self.visaAt ? .visa : .stamp
    }

    /// The country, its titles and what the next level takes.
    var hint: String {
        switch level {
        case .stamp: String(localized: "\(country) · тайтлов: \(titles) · до визы ещё \(Self.visaAt - titles)")
        case .visa: String(localized: "\(country) · тайтлов: \(titles) · до вида на жительство ещё \(Self.residenceAt - titles)")
        case .residence: String(localized: "\(country) · тайтлов: \(titles) · вид на жительство")
        }
    }
}
