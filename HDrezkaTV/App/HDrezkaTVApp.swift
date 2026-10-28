import SwiftUI

@main
struct HDrezkaTVApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        URLCache.shared = URLCache(memoryCapacity: 80 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AuthSession.shared)
                .environment(WatchProgressStore.shared)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                CookieVault.save()
                WatchProgressStore.shared.persist()
            }
        }
    }
}

struct RootView: View {
    @Environment(AuthSession.self) private var auth

    var body: some View {
        if auth.isLoggedIn {
            MainTabView()
        } else {
            LoginView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Главная", systemImage: "house") {
                NavigationStack { HomeView().mediaDestinations() }
            }
            ForEach(CatalogSection.allCases) { section in
                Tab(section.title, systemImage: section.systemImage) {
                    NavigationStack { CatalogView(section: section).mediaDestinations() }
                }
            }
            Tab("Закладки", systemImage: "bookmark") {
                NavigationStack { BookmarksView().mediaDestinations() }
            }
            Tab(role: .search) {
                NavigationStack { SearchView().mediaDestinations() }
            }
            Tab("Настройки", systemImage: "gearshape") {
                NavigationStack { SettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
