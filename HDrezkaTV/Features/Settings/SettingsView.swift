import SwiftUI

struct SettingsView: View {
    @Environment(AuthSession.self) private var auth

    @State private var mirror = Mirror.current.absoluteString
    @State private var mirrorStatus: String?
    @State private var foundMirrors: [URL] = []
    @State private var isSearchingMirrors = false
    @State private var quality = QualityPreference.current
    @State private var confirmLogout = false
    @State private var showAbout = false
    @State private var parentalSheet: ParentalSheet.Mode?
    @State private var showsTour = false

    static let mirrorHint = String(localized: "Напишите на mirror@hdrezka.org, чтобы узнать актуальное зеркало, и введите его сюда.")

    var body: some View {
        Form {
            Section("Аккаунт") {
                LabeledContent("Статус", value: auth.isLoggedIn ? String(localized: "Вход выполнен") : String(localized: "Не выполнен вход"))
                LabeledContent("Подписка", value: auth.isPremium ? "HDrezka Premium" : String(localized: "Обычный аккаунт"))
                Button("Выйти из аккаунта", role: .destructive) { confirmLogout = true }
            }

            Section {
                TextField("https://rezka.fi", text: $mirror)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(applyMirror)
                Button("Применить зеркало", action: applyMirror)
                Button {
                    Task { await findMirrors() }
                } label: {
                    HStack {
                        Text(isSearchingMirrors ? "Ищем рабочие зеркала…" : "Найти рабочее зеркало")
                        if isSearchingMirrors {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isSearchingMirrors)
                ForEach(foundMirrors, id: \.self) { url in
                    Button {
                        apply(url)
                    } label: {
                        LabeledContent(url.host() ?? url.absoluteString, value: url == Mirror.current ? String(localized: "Текущее") : String(localized: "Выбрать"))
                    }
                }
            } header: {
                Text("Зеркало сайта")
            } footer: {
                Text(mirrorStatus ?? Self.mirrorHint + " " + String(localized: "Сессия перенесётся на новое зеркало."))
            }

            Section("Воспроизведение") {
                Picker("Качество по умолчанию", selection: $quality) {
                    // «Лучшее» is kept as is in settings, so only its label is translated.
                    ForEach(QualityPreference.options, id: \.self) { Text($0 == "Лучшее" ? String(localized: "Лучшее") : $0).tag($0) }
                }
                .onChange(of: quality) { _, value in QualityPreference.current = value }
            }

            ParentalSection(sheet: $parentalSheet)

            Section {
                Button("Знакомство с REZKA") { showsTour = true }
                Button("О приложении") { showAbout = true }
            }
        }
        .navigationTitle("Настройки")
        .fullScreenCover(item: $parentalSheet) { mode in
            ParentalSheet(mode: mode)
        }
        .fullScreenCover(isPresented: $showsTour) { OnboardingView() }
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout) {
            Button("Выйти", role: .destructive) { Task { await auth.logout() } }
        }
        .alert("REZKA", isPresented: $showAbout) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(aboutText)
        }
    }

    private var aboutText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let mirror = Mirror.current.host() ?? Mirror.current.absoluteString
        return [
            String(localized: "Версия \(version) (\(build))"),
            String(localized: "Зеркало: \(mirror)"),
            "",
            String(localized: "Неофициальный клиент HDrezka для Apple TV"),
            String(localized: "Разработчик: github.com/mrgsdev"),
        ].joined(separator: "\n")
    }

    private func applyMirror() {
        guard let url = Mirror.normalize(mirror) else {
            mirrorStatus = String(localized: "Некорректный адрес")
            return
        }
        apply(url)
    }

    private func apply(_ url: URL) {
        Mirror.current = url
        mirror = url.absoluteString
        mirrorStatus = String(localized: "Сохранено: \(url.host() ?? url.absoluteString)")
        auth.refresh()
    }

    private func findMirrors() async {
        isSearchingMirrors = true
        mirrorStatus = nil
        foundMirrors = await Mirror.findWorking()
        isSearchingMirrors = false

        if foundMirrors.isEmpty {
            mirrorStatus = String(localized: "Рабочих зеркал не нашли.") + " " + Self.mirrorHint
        } else if foundMirrors.contains(Mirror.current) {
            mirrorStatus = String(localized: "Текущее зеркало работает. Можно выбрать и другое из найденных.")
        } else {
            mirrorStatus = String(localized: "Текущее зеркало не отвечает. Выберите одно из найденных.")
        }
    }
}
