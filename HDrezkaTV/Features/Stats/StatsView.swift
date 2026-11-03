import Charts
import SwiftUI

/// Where «Итоги» lead: the film passport and the achievements.
enum StatsRoute: Hashable {
    case passport
    case achievements
}

/// «Итоги»: how much was watched in REZKA on this Apple TV over a month, a year or all along, by day
/// or month, in which genres, dubs and titles most, and the yearly goal.
struct StatsView: View {
    enum Span: Hashable, CaseIterable {
        case month, year, all

        var title: String {
            switch self {
            case .month: String(localized: "Месяц")
            case .year: String(localized: "Год")
            case .all: String(localized: "Всё время")
            }
        }
    }

    @State private var span = Span.month
    /// A day inside the month or year on screen.
    @State private var anchor = Date()
    @State private var goals = WatchGoal.all
    @State private var isEditingGoal = false

    private let stats = WatchStats.shared
    private let tracker = AchievementTracker.shared
    private let calendar = Calendar.current

    /// Origin tags the site files among genres.
    private static let notGenres: Set<String> = ["Зарубежные", "Русские", "Украинские"]

    var body: some View {
        let summary = summary()
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                header
                    .focusSection()
                links
                    .focusSection()
                if span != .all {
                    goal
                }
                if summary.total < 60 {
                    EmptyStateView(text: String(localized: "Здесь появятся итоги, когда вы что-нибудь посмотрите в REZKA на этом Apple TV."), icon: "chart.bar")
                        .frame(maxWidth: .infinity)
                        .focusPanel()
                } else {
                    tiles(summary)
                    chart(summary)
                    if let interval = calendarInterval {
                        WatchCalendar(interval: interval, seconds: secondsByDay)
                            .focusPanel()
                    }
                    HStack(alignment: .top, spacing: 40) {
                        genres(summary)
                        dubs(summary)
                    }
                    topTitles(summary)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .navigationDestination(for: StatsRoute.self) { route in
            switch route {
            case .passport: FilmPassportView()
            case .achievements: AchievementsView()
            }
        }
        .sheet(isPresented: $isEditingGoal) {
            GoalEditor(year: calendar.component(.year, from: Date()), current: goals[String(calendar.component(.year, from: Date()))]) { films in
                WatchGoal.set(films, for: calendar.component(.year, from: Date()))
                goals = WatchGoal.all
                isEditingGoal = false
                tracker.evaluate(announce: true)
            }
        }
        .onAppear { goals = WatchGoal.all }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 30) {
            // A menu, not segments: the remote's left from a segmented control never reaches the side menu.
            Menu {
                Picker("Период", selection: $span) {
                    ForEach(Span.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } label: {
                Label(span.title, systemImage: "calendar")
                    .fixedSize()
            }

            if span != .all {
                HStack(spacing: 16) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                        .disabled(isFirstPeriod)
                    Text(periodTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minWidth: 280)
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(isCurrentPeriod)
                }
            }
            Spacer()
        }
    }

    /// The film passport and the achievements, each a card with how far along it is.
    private var links: some View {
        HStack(spacing: 40) {
            linkCard(.passport, symbol: "globe.europe.africa.fill", title: "Кинопаспорт",
                     detail: String(localized: "Стран в паспорте: \(FilmPassport.stamps(from: stats).count)"))
            linkCard(.achievements, symbol: "medal.fill", title: "Достижения",
                     detail: String(localized: "Получено \(tracker.earned.count) из \(Achievement.all.count)"))
        }
    }

    private func linkCard(_ route: StatsRoute, symbol: String, title: LocalizedStringKey, detail: String) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 28) {
                Image(systemName: symbol)
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 90, height: 90)
                    .background(Color.accentColor.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(30)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.card)
    }

    private var periodTitle: String {
        switch span {
        case .month:
            let text = anchor.formatted(.dateTime.month(.wide).year())
            return text.prefix(1).uppercased() + text.dropFirst()
        case .year:
            return anchor.formatted(.dateTime.year())
        case .all:
            return Span.all.title
        }
    }

    private var isCurrentPeriod: Bool {
        calendar.isDate(anchor, equalTo: Date(), toGranularity: span == .month ? .month : .year)
    }

    /// November 2026, when «Итоги» began, or its year.
    private var isFirstPeriod: Bool {
        calendar.isDate(anchor, equalTo: WatchStats.firstDay, toGranularity: span == .month ? .month : .year)
    }

    private func shift(_ step: Int) {
        anchor = calendar.date(byAdding: span == .month ? .month : .year, value: step, to: anchor) ?? anchor
    }

    // MARK: Summary

    private struct Summary {
        var total: Double = 0
        /// Seconds by title id.
        var byTitle: [String: Double] = [:]
        /// Seconds by dub.
        var byDub: [String: Double] = [:]
        /// Seconds by bar: a day of the month, or a month of the year or of all time.
        var bars: [Bar] = []
        var activeDays = 0
    }

    private struct Bar: Identifiable {
        let date: Date
        let seconds: Double
        var id: Date { date }
    }

    private func summary() -> Summary {
        var summary = Summary()
        var bars: [Date: Double] = [:]
        for (key, titles) in stats.days {
            guard let day = WatchStats.date(ofDay: key), contains(day) else { continue }
            let seconds = titles.values.reduce(0, +)
            guard seconds > 0 else { continue }
            summary.total += seconds
            summary.activeDays += 1
            for (id, value) in titles { summary.byTitle[id, default: 0] += value }
            let bucket = span == .month
                ? calendar.startOfDay(for: day)
                : calendar.date(from: calendar.dateComponents([.year, .month], from: day)) ?? day
            bars[bucket, default: 0] += seconds
        }
        for (key, dubs) in stats.dubs {
            guard let day = WatchStats.date(ofDay: key), contains(day) else { continue }
            for (dub, value) in dubs { summary.byDub[dub, default: 0] += value }
        }
        summary.bars = bars.map { Bar(date: $0.key, seconds: $0.value) }.sorted { $0.date < $1.date }
        return summary
    }

    private func contains(_ day: Date) -> Bool {
        guard day >= WatchStats.firstDay else { return false }
        return switch span {
        case .month: calendar.isDate(day, equalTo: anchor, toGranularity: .month)
        case .year: calendar.isDate(day, equalTo: anchor, toGranularity: .year)
        case .all: true
        }
    }

    private func titles(_ summary: Summary, of kind: MediaKind) -> Int {
        summary.byTitle.keys.filter { stats.titles[$0]?.kind == kind }.count
    }

    // MARK: Tiles

    private func tiles(_ summary: Summary) -> some View {
        HStack(spacing: 30) {
            tile(Self.hours(summary.total), "Посмотрено", "clock.fill")
            tile("\(titles(summary, of: .film))", "Фильмов", "film.fill")
            tile("\(titles(summary, of: .series))", "Сериалов", "tv.fill")
            tile("\(summary.activeDays)", "Дней с просмотром", "calendar")
        }
        .focusPanel()
    }

    private func tile(_ value: String, _ title: LocalizedStringKey, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Chart

    private func chart(_ summary: Summary) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(span == .month ? "По дням" : "По месяцам")
                .font(.headline)
            Chart(summary.bars) { bar in
                BarMark(
                    x: .value("Дата", bar.date, unit: span == .month ? .day : .month),
                    y: .value("Часы", bar.seconds / 3600)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(6)
            }
            .chartXScale(domain: chartDomain)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hours = value.as(Double.self) { Text(Self.hours(hours * 3600)) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: span == .month ? .day : .month, count: span == .month ? 5 : 1)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: axisFormat, centered: true)
                }
            }
            .frame(height: 340)
        }
        .focusPanel()
    }

    /// All time may run over several years, so its months carry the year.
    private var axisFormat: Date.FormatStyle {
        switch span {
        case .month: .dateTime.day()
        case .year: .dateTime.month(.abbreviated)
        case .all: .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }

    /// The whole month or year, from November 2026 on, so empty days and months show as gaps.
    private var chartDomain: ClosedRange<Date> {
        switch span {
        case .all:
            let end = calendar.dateInterval(of: .month, for: Date())?.end ?? Date()
            return WatchStats.firstDay...max(end, WatchStats.firstDay)
        case .month, .year:
            guard let interval = calendar.dateInterval(of: span == .month ? .month : .year, for: anchor) else { return anchor...anchor }
            return max(interval.start, WatchStats.firstDay)...interval.end
        }
    }

    // MARK: Calendar

    /// The year on screen, or up to the last 52 weeks through this month for all time; a month has its
    /// chart by days. Neither starts before «Итоги» did.
    private var calendarInterval: DateInterval? {
        switch span {
        case .month:
            return nil
        case .year:
            guard let year = calendar.dateInterval(of: .year, for: anchor) else { return nil }
            return DateInterval(start: max(year.start, WatchStats.firstDay), end: max(year.end, WatchStats.firstDay))
        case .all:
            let today = calendar.startOfDay(for: Date())
            guard let yearAgo = calendar.date(byAdding: .day, value: -363, to: today),
                  let end = calendar.dateInterval(of: .month, for: today)?.end else { return nil }
            let start = max(yearAgo, WatchStats.firstDay)
            return DateInterval(start: start, end: max(end, start))
        }
    }

    private var secondsByDay: [Date: Double] {
        Dictionary(stats.days.compactMap { key, titles in
            WatchStats.date(ofDay: key).flatMap { day in
                day >= WatchStats.firstDay ? (calendar.startOfDay(for: day), titles.values.reduce(0, +)) : nil
            }
        }, uniquingKeysWith: +)
    }

    // MARK: Genres and dubs

    private func genres(_ summary: Summary) -> some View {
        var seconds: [String: Double] = [:]
        for (id, value) in summary.byTitle {
            for genre in stats.titles[id]?.genres ?? [] where !Self.notGenres.contains(genre) {
                seconds[genre, default: 0] += value
            }
        }
        let total = seconds.values.reduce(0, +)
        let top = seconds.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
        return bars("Любимые жанры", top, total: total, empty: "У этих тайтлов не нашлось жанров.", showsHours: false)
    }

    /// The studios heard most, by time: the player counts them as it plays.
    private func dubs(_ summary: Summary) -> some View {
        let total = summary.byDub.values.reduce(0, +)
        let top = summary.byDub.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
        return bars("Любимые озвучки", top, total: total, empty: "Посмотрите что-нибудь, и озвучки появятся здесь.", showsHours: true)
    }

    private func bars(_ title: LocalizedStringKey, _ top: [(String, Double)], total: Double, empty: LocalizedStringKey, showsHours: Bool) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(title)
                .font(.headline)
            if top.isEmpty {
                Text(empty)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(top, id: \.0) { name, value in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: name)
                            .lineLimit(1)
                        Spacer()
                        if showsHours {
                            Text(Self.hours(value))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Text((value / total).formatted(.percent.precision(.fractionLength(0))))
                            .foregroundStyle(showsHours ? .primary : .secondary)
                            .monospacedDigit()
                            .frame(minWidth: 80, alignment: .trailing)
                    }
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.accentColor.gradient)
                            .frame(width: max(10, proxy.size.width * value / (top.first?.1 ?? value)))
                    }
                    .frame(height: 10)
                }
            }
        }
        .focusPanel()
    }

    // MARK: Titles

    private func topTitles(_ summary: Summary) -> some View {
        let top = summary.byTitle.sorted { $0.value > $1.value }.prefix(5)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Больше всего смотрели")
                .font(.headline)
                .padding(.bottom, 8)
            ForEach(Array(top), id: \.key) { id, value in
                titleRow(id: id, seconds: value)
            }
        }
        .panel()
    }

    @ViewBuilder
    private func titleRow(id: String, seconds: Double) -> some View {
        let title = stats.titles[id]
        let row = HStack(spacing: 24) {
            PosterImage(url: title?.posterURL)
                .frame(width: 60, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(title?.name ?? String(localized: "Без названия"))
                    .lineLimit(1)
                if let kind = title?.kind.title {
                    Text(kind)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(Self.hours(seconds))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        if let title, let path = title.path {
            NavigationLink(value: MediaItem(path: path, title: title.name, subtitle: "", posterURL: title.posterURL, kind: title.kind, badge: nil)) {
                row
            }
            .buttonStyle(RowButtonStyle())
        } else {
            row.padding(.horizontal, 18)
        }
    }

    // MARK: Goal

    /// The goal of the year on screen, or an offer to set one for this year.
    @ViewBuilder
    private var goal: some View {
        let year = calendar.component(.year, from: anchor)
        if let interval = calendar.dateInterval(of: .year, for: anchor) {
            if let target = goals[String(year)] {
                goalProgress(target, films: tracker.finishedFilms(in: interval), year: year, interval: interval)
            } else if year == calendar.component(.year, from: Date()) {
                HStack(spacing: 24) {
                    Label("Цель на \(String(year))", systemImage: "target")
                        .font(.headline)
                    Text("Сколько фильмов хотите посмотреть за год?")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Поставить цель…") { isEditingGoal = true }
                }
                .panel()
                .focusSection()
            }
        }
    }

    private func goalProgress(_ target: Int, films: [AchievementTracker.FinishedFilm], year: Int, interval: DateInterval) -> some View {
        let now = Date()
        let isThisYear = interval.contains(now)
        // Where an even pace would be by today; the whole year for a year that is over.
        let elapsed = isThisYear ? now.timeIntervalSince(interval.start) / interval.duration : 1
        let done = films.count
        return VStack(alignment: .leading, spacing: 24) {
            HStack {
                Label("Цель на \(String(year))", systemImage: "target")
                    .font(.headline)
                Spacer()
                if isThisYear {
                    Button("Изменить…") { isEditingGoal = true }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("\(done) из \(target)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("фильмов посмотрено")
                    .foregroundStyle(.secondary)
                Spacer()
                Text((Double(done) / Double(target)).formatted(.percent.precision(.fractionLength(0))))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            GoalBar(done: min(Double(done) / Double(target), 1), pace: isThisYear ? elapsed : nil)
            Label(goalPace(target: target, done: done, elapsed: elapsed, interval: interval, isThisYear: isThisYear),
                  systemImage: done >= target ? "checkmark.seal.fill" : "speedometer")
                .foregroundStyle(done >= target ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            if !films.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 24) {
                        ForEach(films, id: \.postId) { goalPoster($0.postId) }
                    }
                    .padding(.vertical, 16)
                }
                .scrollClipDisabled()
            }
        }
        .panel()
        .focusSection()
    }

    /// Ahead or behind an even pace, and what it takes to make it by the end of the year.
    private func goalPace(target: Int, done: Int, elapsed: Double, interval: DateInterval, isThisYear: Bool) -> String {
        if done >= target { return String(localized: "Цель выполнена") }
        guard isThisYear else { return String(localized: "Не хватило: \(target - done)") }
        let behind = Int((Double(target) * elapsed).rounded(.down)) - done
        let pace = behind > 0 ? String(localized: "Отстаёте от плана на \(behind).")
            : behind < 0 ? String(localized: "Опережаете план на \(-behind).")
            : String(localized: "Идёте точно по плану.")
        let weeksLeft = max(interval.end.timeIntervalSinceNow / (7 * 86_400), 1)
        let perWeek = (Double(target - done) / weeksLeft).formatted(.number.precision(.fractionLength(0...1)))
        return pace + " " + String(localized: "Осталось \(target - done), примерно \(perWeek) в неделю.")
    }

    @ViewBuilder
    private func goalPoster(_ postId: String) -> some View {
        let title = stats.titles[postId]
        let poster = PosterImage(url: title?.posterURL)
            .frame(width: 120, height: 180)
        if let title, let path = title.path {
            NavigationLink(value: MediaItem(path: path, title: title.name, subtitle: "", posterURL: title.posterURL, kind: title.kind, badge: nil)) {
                poster
            }
            .buttonStyle(.card)
        } else {
            poster.clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: Formatting

    /// "12 ч 40 мин", "35 мин".
    static func hours(_ seconds: Double) -> String {
        Duration.seconds(Int64(seconds.rounded()))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// The goal's progress, with a tick where an even pace would be by today.
private struct GoalBar: View {
    /// Both from 0 to 1.
    let done: Double
    let pace: Double?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(Color.accentColor.gradient)
                    .frame(width: max(done > 0 ? 18 : 0, width * done))
                if let pace {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.primary.opacity(0.7))
                        .frame(width: 4, height: 28)
                        .offset(x: min(max(width * pace - 2, 0), width - 4))
                }
            }
        }
        .frame(height: 18)
    }
}

/// How many films to watch this year: the usual counts at a press, or one more or less at a time.
private struct GoalEditor: View {
    let year: Int
    let current: Int?
    let save: (Int?) -> Void

    @State private var films: Int
    @Environment(\.dismiss) private var dismiss

    private static let presets = [12, 24, 52, 100]

    init(year: Int, current: Int?, save: @escaping (Int?) -> Void) {
        self.year = year
        self.current = current
        self.save = save
        _films = State(initialValue: current ?? 24)
    }

    var body: some View {
        VStack(spacing: 50) {
            Text("Сколько фильмов посмотреть в \(String(year))?")
                .font(.title2.bold())
            HStack(spacing: 30) {
                ForEach(Self.presets, id: \.self) { preset in
                    Button {
                        films = preset
                    } label: {
                        HStack(spacing: 10) {
                            if films == preset { Image(systemName: "checkmark") }
                            Text(verbatim: "\(preset)")
                        }
                        .frame(minWidth: 120)
                    }
                }
            }
            HStack(spacing: 40) {
                Button { films = max(films - 1, 1) } label: { Image(systemName: "minus") }
                Text(verbatim: "\(films)")
                    .font(.system(size: 90, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 220)
                Button { films = min(films + 1, 999) } label: { Image(systemName: "plus") }
            }
            Text("Цель 12 значит фильм в месяц, 52 значит фильм в неделю. Считаются фильмы, мультфильмы и аниме без серий, досмотренные в REZKA.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 1100)
            HStack(spacing: 30) {
                if current != nil {
                    Button("Убрать цель", role: .destructive) { save(nil) }
                }
                Button("Отмена") { dismiss() }
                Button("Сохранить") { save(films) }
            }
        }
        .padding(80)
    }
}
