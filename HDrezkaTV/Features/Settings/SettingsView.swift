import SwiftUI

struct SettingsView: View {
    @Environment(AuthSession.self) private var auth

    @State private var mirror = Mirror.current.absoluteString
    @State private var mirrorStatus: String?
    @State private var foundMirrors: [URL] = []
    @State private var isSearchingMirrors = false
    @State private var quality = QualityPreference.current
    @State private var confirmLogout = false

    static let mirrorHint = "Напишите на mirror@hdrezka.org, чтобы узнать актуальное зеркало, и введите его сюда."

    var body: some View {
        Form {
            Section("Аккаунт") {
                LabeledContent("Статус", value: auth.isLoggedIn ? "Вход выполнен" : "Не выполнен вход")
                LabeledContent("Подписка", value: auth.isPremium ? "HDrezka Premium" : "Обычный аккаунт")
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
                        LabeledContent(url.host() ?? url.absoluteString, value: url == Mirror.current ? "Текущее" : "Выбрать")
                    }
                }
            } header: {
                Text("Зеркало сайта")
            } footer: {
                Text(mirrorStatus ?? "\(Self.mirrorHint) Сессия перенесётся на новое зеркало.")
            }

            Section("Воспроизведение") {
                Picker("Качество по умолчанию", selection: $quality) {
                    ForEach(QualityPreference.options, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: quality) { _, value in QualityPreference.current = value }
            }

            Section {
                NavigationLink("О приложении") { AboutView() }
            }
        }
        .navigationTitle("Настройки")
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout) {
            Button("Выйти", role: .destructive) { Task { await auth.logout() } }
        }
    }

    private func applyMirror() {
        guard let url = Mirror.normalize(mirror) else {
            mirrorStatus = "Некорректный адрес"
            return
        }
        apply(url)
    }

    private func apply(_ url: URL) {
        Mirror.current = url
        mirror = url.absoluteString
        mirrorStatus = "Сохранено: \(url.host() ?? url.absoluteString)"
        auth.refresh()
    }

    private func findMirrors() async {
        isSearchingMirrors = true
        mirrorStatus = nil
        foundMirrors = await Mirror.findWorking()
        isSearchingMirrors = false

        if foundMirrors.isEmpty {
            mirrorStatus = "Рабочих зеркал не нашли. \(Self.mirrorHint)"
        } else if foundMirrors.contains(Mirror.current) {
            mirrorStatus = "Текущее зеркало работает. Можно выбрать и другое из найденных."
        } else {
            mirrorStatus = "Текущее зеркало не отвечает — выберите одно из найденных."
        }
    }
}
