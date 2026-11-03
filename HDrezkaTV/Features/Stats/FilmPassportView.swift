import SwiftUI

/// The countries visited by watching, as stamps: each with the day the first title from it was
/// watched in REZKA on this Apple TV and how many there have been. A stamp opens the country's list
/// on the site; below them, countries not visited yet.
struct FilmPassportView: View {
    @State private var isFilling = false

    private let stats = WatchStats.shared

    var body: some View {
        let stamps = FilmPassport.stamps(from: stats)
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                cover(stamps)
                    .focusPanel()
                if stamps.isEmpty {
                    EmptyStateView(text: "Паспорт пока пуст. Посмотрите что-нибудь от десяти минут, и первая страна поставит свой штамп.", icon: "globe")
                        .frame(maxWidth: .infinity)
                } else {
                    section("Штампы", note: "Штамп ставится с первого тайтла страны, золотая виза с пятого, вид на жительство с двадцатого.") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 40)], spacing: 40) {
                            ForEach(stamps) { stamp in
                                NavigationLink(value: Listing.country(stamp.country)) {
                                    StampView(stamp: stamp)
                                }
                                .buttonStyle(RowButtonStyle())
                            }
                        }
                    }
                }
                let visited = Set(stamps.map(\.country))
                ForEach(World.continents) { continent in
                    let next = continent.countries.filter { !visited.contains($0) }
                    if !next.isEmpty {
                        section("\(continent.name) · \(continent.countries.count - next.count) из \(continent.countries.count)") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 30)], spacing: 30) {
                                ForEach(next, id: \.self) { trip($0) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .task {
            // Titles watched before «Итоги» kept countries: once, from their pages.
            isFilling = true
            await stats.fillMissingFacts()
            isFilling = false
        }
    }

    // MARK: Cover

    /// What it is, the first country, and how many.
    private func cover(_ stamps: [PassportStamp]) -> some View {
        HStack(alignment: .center, spacing: 30) {
            Image(systemName: "globe.europe.africa.fill")
                .font(.system(size: 54))
                .foregroundStyle(Color.accentColor)
                .frame(width: 110, height: 110)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                Text("Кинопаспорт")
                    .font(.title2.bold())
                Text("Страны, где вы побывали, глядя в экран REZKA на этом Apple TV.")
                    .foregroundStyle(.secondary)
                if let first = stamps.last {
                    Text("Первая страна: \(first.country), \(first.firstDay.formatted(.dateTime.day().month(.wide).year()))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                let visas = stamps.filter { $0.level == .visa }.count
                let residences = stamps.filter { $0.level == .residence }.count
                if visas + residences > 0 {
                    Text("Золотых виз: \(visas) · Видов на жительство: \(residences)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if isFilling {
                    Label("Уточняем страны старых просмотров…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(verbatim: "\(stamps.count)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("Стран в паспорте")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A country not visited yet: its flag in grey and a dashed outline, opening its list.
    private func trip(_ country: String) -> some View {
        NavigationLink(value: Listing.country(country)) {
            VStack(spacing: 10) {
                Text(verbatim: World.flag(for: country))
                    .font(.system(size: 56))
                    .grayscale(1)
                    .opacity(0.6)
                Text(verbatim: country)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
        }
        .buttonStyle(RowButtonStyle())
    }

    private func section(_ title: LocalizedStringKey, note: LocalizedStringKey? = nil, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .font(.headline)
            if let note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .panel()
        .focusSection()
    }
}

/// An ink stamp: the flag, the country, the day of the first visit and how many titles since, in its
/// own ink, shape and tilt, the same every time. A visa is struck in gold; a residence permit is gold
/// and filled, with laurels round the flag.
private struct StampView: View {
    let stamp: PassportStamp

    /// Light enough to read on the dark panels, deep enough on the light ones.
    private static let inks: [Color] = [
        Color(red: 0.93, green: 0.38, blue: 0.38), Color(red: 0.40, green: 0.62, blue: 0.98), Color(red: 0.32, green: 0.78, blue: 0.52),
        Color(red: 0.72, green: 0.52, blue: 0.95), Color(red: 0.96, green: 0.62, blue: 0.30), Color(red: 0.28, green: 0.78, blue: 0.82),
    ]

    /// Stable across launches, unlike `hashValue`.
    private var seed: Int {
        stamp.country.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
    }

    /// Deeper on the light panels, where pale gold would fade into them.
    private static let gold = LinearGradient(
        colors: [
            Brand.adaptive(light: UIColor(red: 0.9, green: 0.65, blue: 0.15, alpha: 1), dark: UIColor(red: 1, green: 0.86, blue: 0.45, alpha: 1)),
            Brand.adaptive(light: UIColor(red: 0.7, green: 0.45, blue: 0.08, alpha: 1), dark: UIColor(red: 0.86, green: 0.6, blue: 0.16, alpha: 1)),
        ],
        startPoint: .top, endPoint: .bottom
    )
    private static let goldGlow = Color(red: 1, green: 0.78, blue: 0.3)

    var body: some View {
        let level = stamp.level
        let ink = level == .stamp ? AnyShapeStyle(Self.inks[seed % Self.inks.count]) : AnyShapeStyle(Self.gold)
        let shape = seed % 3
        let border: CGFloat = level == .residence ? 6 : 4.5
        VStack(spacing: 5) {
            if level != .stamp {
                Text(level == .visa ? "Виза" : "Вид на жительство")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .lineLimit(1)
            }
            HStack(spacing: 4) {
                if level == .residence { Image(systemName: "laurel.leading").font(.system(size: 32)) }
                Text(verbatim: World.flag(for: stamp.country))
                    .font(.system(size: 54))
                if level == .residence { Image(systemName: "laurel.trailing").font(.system(size: 32)) }
            }
            Text(verbatim: stamp.country.uppercased())
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: stamp.firstDay.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year()))
                .font(.system(size: 19, weight: .semibold, design: .monospaced))
            Text(verbatim: "× \(stamp.titles)")
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .opacity(0.8)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(width: shape == 0 ? 230 : 260, height: shape == 0 ? 230 : (level == .stamp ? 190 : 210))
        .background {
            let fill = level == .residence ? AnyShapeStyle(Self.goldGlow.opacity(0.12)) : AnyShapeStyle(Color.clear)
            switch shape {
            case 0:
                Circle().fill(fill)
                    .overlay(Circle().strokeBorder(ink, lineWidth: border))
                    .overlay(Circle().strokeBorder(ink, lineWidth: 2).padding(9))
            case 1:
                Ellipse().fill(fill)
                    .overlay(Ellipse().strokeBorder(ink, lineWidth: border))
                    .overlay(Ellipse().strokeBorder(ink, style: StrokeStyle(lineWidth: 2, dash: [5, 3])).padding(9))
            default:
                RoundedRectangle(cornerRadius: 18).fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(ink, lineWidth: border))
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(ink, lineWidth: 2).padding(9))
            }
        }
        // Gold catches the light; ink never takes evenly.
        .shadow(color: level == .stamp ? .clear : Self.goldGlow.opacity(level == .residence ? 0.5 : 0.3), radius: level == .residence ? 16 : 10)
        .opacity(level == .stamp ? 0.82 : 1)
        .rotationEffect(.degrees(Double(seed % 17) - 8))
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}
