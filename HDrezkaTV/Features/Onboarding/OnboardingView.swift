import SwiftUI

/// A tour of the app, shown once after signing in and again from Settings: a page for each part of
/// it, with what it does and where it lives.
struct OnboardingView: View {
    struct Feature: Hashable {
        let symbol: String
        let title: String
        let text: String
    }

    struct Page: Identifiable {
        enum Art {
            case logo
            case symbol(String)
            case medal(String)
        }

        let id: Int
        let art: Art
        let title: String
        let subtitle: String
        let features: [Feature]
        /// Short labels floating round the picture.
        let chips: [String]
        /// The last page: its subtitle is the developer's note, and the disclaimer stands in for features.
        var isFarewell = false
    }

    /// The same points as on the Mac, put shortly.
    static let disclaimer = [
        String(localized: "Программа предоставляется «как есть», без каких-либо гарантий."),
        String(localized: "REZKA не связана с HDrezka и не является её официальным клиентом."),
        String(localized: "REZKA ничего не размещает и не хранит. Фильмы, сериалы, постеры и описания принадлежат правообладателям."),
        String(localized: "Автор не поощряет какую-либо незаконную деятельность."),
        String(localized: "Используйте программу на свой страх и риск и соблюдайте законы своей страны."),
    ]

    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboardingSeen") private var isSeen = false
    @State private var index = 0
    @State private var isForward = true
    @State private var isFloating = false
    @FocusState private var isNextFocused: Bool

    static let pages: [Page] = [
        Page(id: 0, art: .logo,
             title: String(localized: "Добро пожаловать в REZKA"),
             subtitle: String(localized: "Неофициальный клиент HDrezka для Apple TV. Быстрый, нативный и с вещами, которых нет на сайте."),
             features: [
                Feature(symbol: "play.rectangle.fill", title: String(localized: "Смотрите на большом экране"),
                        text: String(localized: "Родной плеер Apple TV и продолжение с того же места на любом устройстве.")),
                Feature(symbol: "sparkles", title: String(localized: "Больше, чем на сайте"),
                        text: String(localized: "Рулетка, итоги, достижения, кинопаспорт и детский режим.")),
                Feature(symbol: "lock.shield", title: String(localized: "Ваши данные у вас"),
                        text: String(localized: "Статистика и достижения хранятся только на этом Apple TV.")),
             ],
             chips: [String(localized: "Фильмы"), String(localized: "Сериалы"), String(localized: "Мультфильмы"), String(localized: "Аниме")]),
        Page(id: 1, art: .symbol("square.grid.2x2.fill"),
             title: String(localized: "Каталог и поиск"),
             subtitle: String(localized: "Всё, что есть на сайте, в разделах бокового меню."),
             features: [
                Feature(symbol: "film", title: String(localized: "Разделы и жанры"),
                        text: String(localized: "Фильмы, сериалы, мультфильмы, аниме, передачи и шоу. Жанры и лучшие по годам.")),
                Feature(symbol: "square.stack", title: String(localized: "Подборки и закладки"),
                        text: String(localized: "Подборки сайта и ваши папки закладок.")),
                Feature(symbol: "magnifyingglass", title: String(localized: "Поиск"),
                        text: String(localized: "Ищите по названию во вкладке «Поиск».")),
                Feature(symbol: "info.circle", title: String(localized: "Подсказка на постере"),
                        text: String(localized: "Задержите фокус на постере, и рядом появятся рейтинг и описание.")),
             ],
             chips: [String(localized: "Жанры"), String(localized: "Подборки"), String(localized: "Лучшие"), String(localized: "Закладки")]),
        Page(id: 2, art: .symbol("film.stack.fill"),
             title: String(localized: "Карточка тайтла"),
             subtitle: String(localized: "Всё о фильме или сериале на одной странице."),
             features: [
                Feature(symbol: "waveform", title: String(localized: "Озвучки"),
                        text: String(localized: "Выбор озвучки, её сезоны и какую выбирают зрители.")),
                Feature(symbol: "list.number", title: String(localized: "Сезоны и график"),
                        text: String(localized: "Серии с прогрессом, даты выхода и отметки «просмотрено».")),
                Feature(symbol: "star.fill", title: String(localized: "Оценки и отзывы"),
                        text: String(localized: "IMDb, Кинопоиск, ваша оценка и лайки отзывам долгим нажатием.")),
                Feature(symbol: "person.2.fill", title: String(localized: "Актёры и трейлер"),
                        text: String(localized: "Страницы режиссёров и актёров, трейлер в YouTube или по QR-коду.")),
             ],
             chips: ["IMDb", String(localized: "Озвучки"), String(localized: "Трейлер"), String(localized: "Франшиза")]),
        Page(id: 3, art: .symbol("play.circle.fill"),
             title: String(localized: "Плеер"),
             subtitle: String(localized: "Родной плеер Apple TV со всем, что нужно для сериалов."),
             features: [
                Feature(symbol: "clock.arrow.circlepath", title: String(localized: "Продолжение"),
                        text: String(localized: "Позиция сохраняется и уходит на сайт, так что смотреть можно и на других устройствах.")),
                Feature(symbol: "forward.end.fill", title: String(localized: "Следующая серия"),
                        text: String(localized: "Включается сама после конца серии или из меню плеера.")),
                Feature(symbol: "captions.bubble", title: String(localized: "Субтитры, скорость, качество"),
                        text: String(localized: "В меню плеера. Качество по умолчанию выбирается в Настройках.")),
                Feature(symbol: "arrow.down.circle", title: String(localized: "Загрузка"),
                        text: String(localized: "Под названием видно, насколько фильм или серия загрузились для быстрой перемотки.")),
             ],
             chips: ["1080p", "1,5×", String(localized: "Субтитры"), String(localized: "Озвучка")]),
        Page(id: 4, art: .symbol("dice.fill"),
             title: String(localized: "Что посмотреть?"),
             subtitle: String(localized: "Когда не можете выбрать, пусть выберет случай."),
             features: [
                Feature(symbol: "dice", title: String(localized: "Рулетка"),
                        text: String(localized: "Барабан из постеров крутится и останавливается на фильме.")),
                Feature(symbol: "slider.horizontal.3", title: String(localized: "Фильтры"),
                        text: String(localized: "Раздел, жанры, страны, годы и рейтинг IMDb.")),
             ],
             chips: [String(localized: "IMDb от 7"), String(localized: "Жанры"), String(localized: "Страны"), String(localized: "Годы")]),
        Page(id: 5, art: .medal("films-100"),
             title: String(localized: "Итоги"),
             subtitle: String(localized: "Сколько, когда и что вы смотрели в REZKA."),
             features: [
                Feature(symbol: "chart.bar.xaxis", title: String(localized: "Часы и календарь"),
                        text: String(localized: "График по месяцам и календарь просмотров, как вклады на GitHub.")),
                Feature(symbol: "target", title: String(localized: "Цель на год"),
                        text: String(localized: "Сколько фильмов хотите посмотреть и как идёте по плану.")),
                Feature(symbol: "globe.europe.africa.fill", title: String(localized: "Кинопаспорт"),
                        text: String(localized: "Штампы стран, золотые визы и вид на жительство.")),
                Feature(symbol: "medal.fill", title: String(localized: "Достижения"),
                        text: String(localized: "Медали в стиле Apple Watch за фильмы, сериалы, привычки и страны.")),
             ],
             chips: [String(localized: "Цель"), String(localized: "Паспорт"), String(localized: "Медали"), String(localized: "Озвучки")]),
        Page(id: 6, art: .symbol("lock.shield.fill"),
             title: String(localized: "Детский режим"),
             subtitle: String(localized: "Спокойствие, если телевизор смотрят дети. Включается в Настройках."),
             features: [
                Feature(symbol: "figure.and.child.holdinghands", title: String(localized: "Возраст"),
                        text: String(localized: "0+, 6+, 12+ или 16+. Всё, что старше, скрыто и не запускается.")),
                Feature(symbol: "lock.fill", title: String(localized: "PIN-код"),
                        text: String(localized: "Изменить или выключить режим можно только с PIN-кодом.")),
                Feature(symbol: "key.fill", title: String(localized: "Код восстановления"),
                        text: String(localized: "Если PIN забыт, поможет код, который показывается один раз.")),
             ],
             chips: ["0+", "6+", "12+", "16+"]),
        Page(id: 7, art: .symbol("lightbulb.fill"),
             title: String(localized: "Полезные мелочи"),
             subtitle: String(localized: "Несколько вещей, которые пригодятся каждый день."),
             features: [
                Feature(symbol: "sidebar.left", title: String(localized: "Боковое меню"),
                        text: String(localized: "Нажмите влево, чтобы перейти в другой раздел.")),
                Feature(symbol: "hand.tap", title: String(localized: "Долгое нажатие"),
                        text: String(localized: "Уберёт постер из «Продолжить просмотр» и поставит лайк отзыву.")),
                Feature(symbol: "arrow.triangle.2.circlepath", title: String(localized: "Зеркала"),
                        text: String(localized: "Если сайт не открывается, найдите рабочее зеркало в Настройках.")),
                Feature(symbol: "questionmark.circle", title: String(localized: "Это знакомство"),
                        text: String(localized: "Открывается снова в Настройках.")),
             ],
             chips: [String(localized: "Меню"), String(localized: "Настройки"), String(localized: "Зеркала"), String(localized: "Закладки")]),
        Page(id: 8, art: .symbol("heart.text.square.fill"),
             title: String(localized: "Пара слов от разработчика"),
             subtitle: String(localized: "Я сделал REZKA для себя, потому что сам смотрю через неё фильмы и сериалы каждый день. Буду рад, если приложение пригодится и вам. Только, пожалуйста, помните о правилах сайта."),
             features: [],
             chips: [String(localized: "Для себя"), String(localized: "Открытый код"), "MIT", String(localized: "Бесплатно")],
             isFarewell: true),
    ]

    private var page: Page { Self.pages[index] }
    private var isLast: Bool { index == Self.pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                content(page)
                    .id(page.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: isForward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: isForward ? .leading : .trailing).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            footer
                .padding(.horizontal, 100)
                .padding(.bottom, 60)
        }
        .background {
            ZStack {
                Color.black
                RadialGradient(colors: [Color.accentColor.opacity(0.3), .clear], center: UnitPoint(x: 0.25, y: 0.42), startRadius: 0, endRadius: 900)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { isFloating = true }
            isNextFocused = true
        }
        // Menu leaves the tour as «Пропустить» does.
        .onDisappear { isSeen = true }
    }

    // MARK: Page

    private func content(_ page: Page) -> some View {
        HStack(spacing: 90) {
            art(page)
                .frame(width: 600, height: 700)
            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(page.title)
                        .font(.system(size: 64, weight: .bold))
                    if !page.isFarewell {
                        Text(page.subtitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if page.isFarewell {
                    farewell(page)
                } else {
                    features(page)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 100)
    }

    private func features(_ page: Page) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(page.features, id: \.self) { feature in
                HStack(alignment: .top, spacing: 28) {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 72, height: 72)
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(feature.title)
                            .font(.headline)
                        Text(feature.text)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The developer's note in a card, then the disclaimer point by point and where the site's rules are.
    private func farewell(_ page: Page) -> some View {
        VStack(alignment: .leading, spacing: 30) {
            Text(page.subtitle)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 26)
                .padding(.leading, 40)
                .padding(.trailing, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.panel, in: RoundedRectangle(cornerRadius: 24))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 6)
                        .padding(.vertical, 22)
                        .padding(.leading, 16)
                }
            VStack(alignment: .leading, spacing: 12) {
                Label("Отказ от ответственности", systemImage: "exclamationmark.shield.fill")
                    .font(.headline)
                    .padding(.bottom, 4)
                ForEach(Self.disclaimer, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(verbatim: "•")
                            .foregroundStyle(Color.accentColor)
                        Text(line)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption)
                }
            }
            Label("Правила сайта HDrezka: rezka.ag/rules", systemImage: "doc.text")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
        }
    }

    /// Two tilted tiles behind the page's picture, with its labels floating round them.
    private func art(_ page: Page) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 70)
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.45), Color.accentColor.opacity(0.08)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 380, height: 380)
                .rotationEffect(.degrees(-9))
            RoundedRectangle(cornerRadius: 70)
                .fill(Brand.panel)
                .overlay(RoundedRectangle(cornerRadius: 70).strokeBorder(Brand.stroke, lineWidth: 2))
                .frame(width: 380, height: 380)
                .rotationEffect(.degrees(6))
                .shadow(color: .black.opacity(0.25), radius: 36, y: 18)

            switch page.art {
            case .logo:
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300)
            case let .symbol(name):
                Image(systemName: name)
                    .font(.system(size: 150, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 30)
            case let .medal(id):
                if let medal = Achievement.all.first(where: { $0.id == id })?.medal {
                    MedalView(medal: medal, size: 300)
                }
            }

            ForEach(Array(page.chips.enumerated()), id: \.offset) { index, chip in
                Text(verbatim: chip)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Brand.stroke))
                    .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
                    .offset(Self.chipPlaces[index % Self.chipPlaces.count])
                    .offset(y: isFloating ? (index.isMultiple(of: 2) ? -10 : 10) : 0)
            }
        }
    }

    private static let chipPlaces = [CGSize(width: -200, height: -240), CGSize(width: 210, height: -170),
                                     CGSize(width: -220, height: 190), CGSize(width: 196, height: 250)]

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 30) {
            HStack(spacing: 12) {
                ForEach(Self.pages) { item in
                    Capsule()
                        .fill(item.id == index ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: item.id == index ? 44 : 16, height: 16)
                }
            }
            .animation(.easeOut(duration: 0.25), value: index)
            Spacer()
            if !isLast {
                Button("Пропустить", action: finish)
            }
            if index > 0 {
                Button("Назад") { go(to: index - 1) }
            }
            Button(isLast ? "Начать" : "Далее") {
                if isLast { finish() } else { go(to: index + 1) }
            }
            .focused($isNextFocused)
        }
        .focusSection()
    }

    private func go(to target: Int) {
        guard target != index, Self.pages.indices.contains(target) else { return }
        isForward = target > index
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { index = target }
        isNextFocused = true
    }

    private func finish() {
        isSeen = true
        dismiss()
    }
}
