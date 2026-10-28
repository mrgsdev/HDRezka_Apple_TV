import SwiftUI

struct SettingsView: View {
    @Environment(AuthSession.self) private var auth

    @State private var mirror = Mirror.current.absoluteString
    @State private var mirrorStatus: String?
    @State private var quality = QualityPreference.current
    @State private var confirmLogout = false

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
            } header: {
                Text("Зеркало сайта")
            } footer: {
                Text(mirrorStatus ?? "Если сайт перестал открываться, укажите другой адрес HDrezka. Сессия перенесётся на новое зеркало.")
            }

            Section("Воспроизведение") {
                Picker("Качество по умолчанию", selection: $quality) {
                    ForEach(QualityPreference.options, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: quality) { _, value in QualityPreference.current = value }
            }

            Section("О приложении") {
                Text("Неофициальный клиент HDrezka для Apple TV. Идеи и разбор API — из открытых проектов rezka-payer и hdrezka-swiftui.")
                    .foregroundStyle(.secondary)
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
        Mirror.current = url
        mirror = url.absoluteString
        mirrorStatus = "Сохранено: \(url.host() ?? url.absoluteString)"
        auth.refresh()
    }
}
