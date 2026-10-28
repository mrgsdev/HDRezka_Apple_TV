import SwiftUI

struct AboutView: View {
    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    private static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"

    var body: some View {
        VStack(spacing: 50) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 520)

            VStack(spacing: 12) {
                Text("Версия \(Self.version) (\(Self.build))")
                    .font(.title2.bold())
                Text("Зеркало: \(Mirror.current.host() ?? Mirror.current.absoluteString)")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Text("Неофициальный клиент HDrezka для Apple TV")
                Text("Разработчик: github.com/mrgsdev")
            }
            .foregroundStyle(.secondary)
        }
        // Without anything focusable the Menu button sends the app to the Home Screen
        // instead of going back to Settings.
        .focusable()
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("О приложении")
    }
}
