import SwiftUI

/// "Что посмотреть?": a reel of posters that spins to a random title, or shows one at once, with what
/// it landed on and buttons to watch it or roll again.
struct RouletteView: View {
    @State private var model = RouletteModel()
    /// Picks at once instead of spinning the reel; remembered on this Apple TV.
    @AppStorage("rouletteWithoutAnimation") private var withoutAnimation = false
    @State private var choosing: Choice?

    private enum Choice: String, Identifiable {
        case genres, countries
        var id: String { rawValue }
    }

    private var menu: SectionMenu? { SiteMenu.shared.menus[model.section] }

    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                filters
                    .focusSection()
                RouletteReel(model: model)
                    .frame(height: 560)
                    .overlay {
                        if model.phase == .loading { LoadingPill() }
                    }
                controls
                    .focusSection()
                if model.phase == .done, let pick = model.pick {
                    RouletteResult(model: pick)
                        .focusSection()
                        .transition(.opacity.combined(with: .offset(y: 16)))
                } else if let error = model.error {
                    Text(error.localizedDescription)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 1200)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
            .animation(.easeOut(duration: 0.3), value: model.phase == .done)
            .animation(.easeOut(duration: 0.25), value: model.phase == .loading)
        }
        .scrollClipDisabled()
        .task { await SiteMenu.shared.loadIfNeeded() }
        .task(id: model.key) {
            // A pause first, so ticking several genres in a row loads once.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await model.prepare()
        }
        .sheet(item: $choosing) { choice in
            switch choice {
            case .genres:
                MultiChoice(
                    title: String(localized: "Жанры"),
                    options: (menu?.genres ?? []).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending },
                    selection: $model.genres, label: \.title
                )
            case .countries:
                MultiChoice(title: String(localized: "Страны"), options: RouletteModel.countryOptions, selection: $model.countries) { $0 }
            }
        }
    }

    // MARK: Filters

    /// As on Kinopoisk's random film page: what kind, which genres and countries, which years and rating.
    private var filters: some View {
        VStack(spacing: 30) {
            Picker("Раздел", selection: $model.section) {
                // Not shows: they are mostly concerts, which the roulette leaves out.
                ForEach(CatalogSection.allCases.filter { $0 != .show }) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .focusSection()

            HStack(spacing: 24) {
                filterButtons
            }
            .fixedSize()
            .focusSection()
        }
        .disabled(model.phase == .spinning)
    }

    @ViewBuilder
    private var filterButtons: some View {
        Button { choosing = .genres } label: {
            Label(summary(model.genres.map(\.title), empty: String(localized: "Все жанры"), many: String(localized: "Жанры")), systemImage: "theatermasks")
                .lineLimit(1)
        }
        .disabled(menu == nil)

        Button { choosing = .countries } label: {
            Label(summary(Array(model.countries), empty: String(localized: "Все страны"), many: String(localized: "Страны")), systemImage: "globe")
                .lineLimit(1)
        }

        yearsMenu
        imdbMenu

        if model.hasFilters {
            Button("Сбросить", action: model.resetFilters)
        }
    }

    private func summary(_ picked: [String], empty: String, many: String) -> String {
        switch picked.count {
        case 0: empty
        case 1: picked[0]
        default: "\(many): \(picked.count)"
        }
    }

    /// Spans of years instead of a slider, which the remote has no way to drag.
    private static var yearSpans: [(title: String, years: ClosedRange<Int>)] {
        let now = Calendar.current.component(.year, from: Date())
        let decades = stride(from: (now / 10) * 10, through: 1970, by: -10).map { start in
            (String(localized: "\(String(start))-е"), start...min(start + 9, now))
        }
        return [(String(localized: "Все годы"), RouletteModel.allYears), (String(localized: "Последние 3 года"), (now - 2)...now)]
            + decades + [(String(localized: "До 1970"), RouletteModel.allYears.lowerBound...1969)]
    }

    private var yearsMenu: some View {
        let current = Self.yearSpans.first { $0.years == model.years }?.title ?? "\(model.years.lowerBound)–\(model.years.upperBound)"
        return Menu {
            ForEach(Self.yearSpans, id: \.title) { span in
                Button {
                    model.years = span.years
                } label: {
                    if span.years == model.years {
                        Label(span.title, systemImage: "checkmark")
                    } else {
                        Text(span.title)
                    }
                }
            }
        } label: {
            Label(current, systemImage: "calendar")
                .lineLimit(1)
        }
    }

    private var imdbMenu: some View {
        Menu {
            Button {
                model.minIMDb = nil
            } label: {
                if model.minIMDb == nil {
                    Label("Любой рейтинг IMDb", systemImage: "checkmark")
                } else {
                    Text("Любой рейтинг IMDb")
                }
            }
            ForEach(RouletteModel.imdbOptions, id: \.self) { value in
                Button {
                    model.minIMDb = value
                } label: {
                    if model.minIMDb == value {
                        Label("IMDb от \(value.formatted())", systemImage: "checkmark")
                    } else {
                        Text("IMDb от \(value.formatted())")
                    }
                }
            }
        } label: {
            Label(model.minIMDb.map { String(localized: "IMDb от \($0.formatted())") } ?? String(localized: "Любой IMDb"), systemImage: "star")
                .lineLimit(1)
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 40) {
            Button {
                Task { await model.roll(animated: !withoutAnimation) }
            } label: {
                Label(model.phase == .done ? "Крутить ещё" : "Крутить", systemImage: "dice.fill")
                    .frame(minWidth: 280)
            }
            // Nothing to roll from until the first list has come, unless it failed and a roll should retry.
            .disabled(model.isBusy || (model.reel.isEmpty && model.error == nil))

            Toggle("Без анимации", isOn: $withoutAnimation)
                .fixedSize()
        }
    }
}

/// The posters in a row: the one in the middle full size and lit from behind, the others smaller
/// and dimmer the further out. While the reel spins, its position comes from the spin each frame.
private struct RouletteReel: View {
    let model: RouletteModel

    /// Space between neighbouring cards whatever their size.
    private static let gap: CGFloat = 30
    /// Cards shrink this much per step from the middle, down to `minScale`.
    private static let shrink: CGFloat = 0.16
    private static let minScale: CGFloat = 0.62

    var body: some View {
        GeometryReader { proxy in
            let width = min(340, (proxy.size.height - 60) / 1.5)
            TimelineView(.animation(paused: model.spin == nil)) { context in
                let position = model.spin?.position(at: context.date) ?? model.position
                ZStack {
                    glow(width: width)
                    ForEach(visibleIndices(around: position), id: \.self) { index in
                        let distance = Double(index) - position
                        card(model.reel[index], width: width, distance: distance)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private func visibleIndices(around position: Double) -> [Int] {
        guard !model.reel.isEmpty else { return [] }
        let middle = Int(position.rounded())
        return Array(max(0, middle - 6)...min(model.reel.count - 1, middle + 6))
    }

    private func card(_ item: MediaItem, width: CGFloat, distance: Double) -> some View {
        let away = abs(CGFloat(distance))
        return ReelCard(item: item, width: width, isLit: away < 0.5)
            .scaleEffect(max(Self.minScale, 1 - Self.shrink * away))
            .opacity(1 - 0.28 * min(away, 2.5))
            .blur(radius: min(away, 2) * 1.5)
            .offset(x: offset(for: CGFloat(distance), width: width))
            .zIndex(-Double(away))
    }

    /// Centre-to-centre distance summed over the shrinking widths between here and the middle,
    /// so the gaps stay even as the cards get smaller.
    private func offset(for distance: CGFloat, width: CGFloat) -> CGFloat {
        let away = abs(distance)
        let flat = (1 - Self.minScale) / Self.shrink
        let covered = away <= flat
            ? away - Self.shrink / 2 * away * away
            : flat - Self.shrink / 2 * flat * flat + Self.minScale * (away - flat)
        return (covered * width + Self.gap * away) * (distance < 0 ? -1 : 1)
    }

    private func glow(width: CGFloat) -> some View {
        let color = model.glow ?? Color(red: 0.85, green: 0.1, blue: 0.12)
        return Ellipse()
            .fill(RadialGradient(colors: [color.opacity(0.7), color.opacity(0)], center: .center, startRadius: 0, endRadius: width * 1.5))
            .frame(width: width * 4.2, height: width * 1.55)
            .blur(radius: 36)
            .allowsHitTesting(false)
    }
}

/// A poster with its title and year over the bottom, as on the reel.
private struct ReelCard: View {
    let item: MediaItem
    let width: CGFloat
    let isLit: Bool

    var body: some View {
        PosterImage(url: item.posterURL)
            .frame(width: width, height: width * 1.5)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .padding(20)
                .padding(.top, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(isLit ? 0.25 : 0.1), lineWidth: 2))
            .shadow(color: .black.opacity(isLit ? 0.5 : 0.2), radius: isLit ? 36 : 12, y: 14)
    }
}

/// What the reel stopped on: the title, ratings and description from its page, and the buttons to watch it.
private struct RouletteResult: View {
    let model: DetailsModel
    @Environment(WatchProgressStore.self) private var progress

    var body: some View {
        VStack(spacing: 16) {
            Text(model.item.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if !model.item.subtitle.isEmpty {
                Text(model.item.subtitle)
                    .foregroundStyle(.secondary)
            }
            if let details = model.details {
                if let ratings = details.info("Рейтинги") {
                    Label(ratings, systemImage: "star.fill")
                        .foregroundStyle(Brand.gold)
                }
                if !details.description.isEmpty {
                    Text(details.description)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 1300)
                }
            } else {
                ProgressView()
            }
            HStack(spacing: 30) {
                watchButton
                NavigationLink(value: model.item) {
                    Label("Открыть карточку", systemImage: "info.circle")
                }
            }
            .padding(.top, 10)
        }
    }

    /// Same choice as the title page's main button: the next episode, or the film from where it stopped.
    @ViewBuilder
    private var watchButton: some View {
        if model.details?.restriction != nil {
            Label("Недоступно в вашем регионе", systemImage: "globe")
                .foregroundStyle(.secondary)
        } else if let details = model.details, details.upcomingStatus == nil {
            if details.isSeries {
                if let target = model.resumeEpisode(progress: progress) {
                    Button {
                        model.play(episode: target.episode)
                    } label: {
                        Label(target.entry == nil ? "Смотреть" : "Продолжить", systemImage: "play.fill")
                    }
                } else if model.isLoadingEpisodes {
                    ProgressView()
                }
            } else {
                let entry = progress.entry(postId: details.postId, seasonId: nil, episodeId: nil)
                let resumes = entry.map { !$0.isFinished && $0.position > 30 } ?? false
                Button {
                    model.play(from: resumes ? nil : 0)
                } label: {
                    Label(resumes ? "Продолжить" : "Смотреть", systemImage: "play.fill")
                }
            }
        }
    }
}

/// A sheet of options to tick any number of, for genres and countries.
private struct MultiChoice<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Set<Option>
    let label: (Option) -> String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 30) {
            Text(title)
                .font(.title2.bold())
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: 3), spacing: 24) {
                    ForEach(options, id: \.self) { option in
                        let isOn = selection.contains(option)
                        Button {
                            if isOn { selection.remove(option) } else { selection.insert(option) }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                                Text(label(option))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(40)
            }
            HStack(spacing: 30) {
                Button("Сбросить") { selection = [] }
                    .disabled(selection.isEmpty)
                Button("Готово") { dismiss() }
            }
        }
        .padding(.vertical, 40)
        // Wide enough for «Биографические» in three columns; a sheet is only as wide as its content.
        .frame(width: 1400)
    }
}

/// Over the reel while titles for the new filters load.
private struct LoadingPill: View {
    var body: some View {
        HStack(spacing: 18) {
            ProgressView()
            Text("Загружается, подождите…")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Brand.stroke))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 6)
        .transition(.opacity)
    }
}
