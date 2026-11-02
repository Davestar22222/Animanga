import SwiftUI
import AVFoundation

@main
struct AniMangaApp: App {
    @StateObject private var library = LibraryStore()

    init() {
        // Большой кэш для обложек и страниц манги.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                   diskCapacity: 768 * 1024 * 1024)
        // Звук воспроизводится даже при выключенном беззвучном режиме.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .tint(.pink)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            AnimeBrowseView()
                .tabItem { Label("Аниме", systemImage: "play.tv") }
            MangaBrowseView()
                .tabItem { Label("Манга", systemImage: "book") }
            LibraryView()
                .tabItem { Label("Библиотека", systemImage: "heart") }
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape") }
        }
    }
}
