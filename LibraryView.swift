import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                Picker("Раздел", selection: $tab) {
                    Text("Недавние").tag(0)
                    Text("Аниме").tag(1)
                    Text("Манга").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                content
            }
            .navigationTitle("Библиотека")
            .navigationDestination(for: Anime.self) { AnimeDetailView(anime: $0) }
            .navigationDestination(for: Manga.self) { MangaDetailView(manga: $0) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case 0: history
        case 1: favoritesAnime
        default: favoritesManga
        }
    }

    private var history: some View {
        LazyVStack(spacing: 0) {
            if library.state.history.isEmpty {
                empty("Здесь появятся недавно просмотренные серии и прочитанные главы.")
            }
            ForEach(library.state.history) { entry in
                Group {
                    if let a = entry.anime {
                        NavigationLink(value: a) { historyRow(entry) }
                    } else if let m = entry.manga {
                        NavigationLink(value: m) { historyRow(entry) }
                    }
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 80)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func historyRow(_ e: HistoryEntry) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: e.coverURL)
                .frame(width: 52, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(e.title).font(.subheadline.bold()).lineLimit(2)
                Text(e.detail).font(.footnote).foregroundStyle(.secondary)
                Text(e.date, style: .relative).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: e.kind == .anime ? "play.tv" : "book").foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var favoritesAnime: some View {
        Group {
            if library.state.favAnime.isEmpty {
                empty("Нажмите ♡ на странице аниме, чтобы добавить в избранное.")
            } else {
                LazyVGrid(columns: posterColumns, spacing: 16) {
                    ForEach(library.state.favAnime) { a in
                        NavigationLink(value: a) { PosterCard(title: a.title, cover: a.coverURL) }
                            .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }

    private var favoritesManga: some View {
        Group {
            if library.state.favManga.isEmpty {
                empty("Нажмите ♡ на странице манги, чтобы добавить в избранное.")
            } else {
                LazyVGrid(columns: posterColumns, spacing: 16) {
                    ForEach(library.state.favManga) { m in
                        NavigationLink(value: m) { PosterCard(title: m.title, cover: m.coverURL) }
                            .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @AppStorage("mangaLang") private var lang = "en"
    @AppStorage("dataSaver") private var dataSaver = false
    @AppStorage("readerMode") private var mode = "paged"
    @AppStorage("readerRTL") private var rtl = false
    @AppStorage("preferRussian") private var preferRussian = true
    @State private var cacheCleared = false

    private let languages: [(code: String, name: String)] = [
        ("en", "English"), ("ru", "Русский"), ("uk", "Українська"), ("es", "Español"),
        ("es-la", "Español (LatAm)"), ("fr", "Français"), ("de", "Deutsch"), ("it", "Italiano"),
        ("pt-br", "Português (BR)"), ("id", "Indonesia"), ("tr", "Türkçe"), ("pl", "Polski"),
        ("ja", "日本語"), ("zh", "中文")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Аниме") {
                    Toggle("Русские название и описание (Shikimori)", isOn: $preferRussian)
                }

                Section("Манга") {
                    Picker("Язык перевода", selection: $lang) {
                        ForEach(languages, id: \.code) { Text($0.name).tag($0.code) }
                    }
                    Picker("Режим чтения", selection: $mode) {
                        Text("Постранично").tag("paged")
                        Text("Лента (вебтун)").tag("webtoon")
                    }
                    Toggle("Справа налево", isOn: $rtl)
                    Toggle("Экономия трафика", isOn: $dataSaver)
                }

                Section("Данные") {
                    Button("Очистить кэш изображений") {
                        URLCache.shared.removeAllCachedResponses()
                        cacheCleared = true
                    }
                    Button("Очистить историю", role: .destructive) { library.clearHistory() }
                    if cacheCleared { Text("Кэш очищен").font(.footnote).foregroundStyle(.secondary) }
                }

                Section("О приложении") {
                    Text("Каталог аниме и метаданные — AniList, русские названия, описания и оценки — Shikimori. Каталог и главы манги — MangaDex (переводы выкладывают сами сообщества и издатели). Видео аниме в приложении не поставляется: вы подключаете собственные ссылки или файлы для каждой серии.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Видеофайлы можно скинуть на устройство (AirDrop, «Файлы»), а затем выбрать при добавлении источника серии: нажмите на серию → «Выбрать видеофайл».")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Настройки")
        }
    }
}
