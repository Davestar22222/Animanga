import SwiftUI

struct AnimeDetailView: View {
    let anime: Anime
    @EnvironmentObject private var library: LibraryStore

    enum SheetKind: Identifiable {
        case add(Int)
        case bulk
        var id: String {
            switch self {
            case .add(let n): return "add\(n)"
            case .bulk: return "bulk"
            }
        }
    }

    struct PlayItem: Identifiable {
        let id = UUID()
        let number: Int
        let url: URL
    }

    @State private var sheet: SheetKind?
    @State private var playing: PlayItem?
    @State private var ru: ShikimoriService.Info?
    @AppStorage("preferRussian") private var preferRussian = true

    private var russianTitle: String? {
        guard preferRussian, let t = ru?.russianTitle, t != anime.title else { return nil }
        return t
    }

    private var synopsis: String {
        if preferRussian, let d = ru?.description, !d.isEmpty { return d }
        return anime.synopsis
    }

    private var episodeCount: Int {
        let maxSource = library.sourceNumbers(animeID: anime.id).max() ?? 0
        let base = anime.episodes ?? 12
        return min(1500, max(1, max(base, maxSource)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                actions
                ExpandableText(text: synopsis)
                if !anime.genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(anime.genres, id: \.self) { Chip(text: $0) } }
                    }
                }
                Divider()
                episodesSection
            }
            .padding()
        }
        .navigationTitle(anime.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: anime.malID) {
            guard let id = anime.malID else { return }
            ru = try? await ShikimoriService.info(malID: id)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    library.toggleFavorite(anime)
                } label: {
                    Image(systemName: library.isFavorite(anime) ? "heart.fill" : "heart")
                }
            }
        }
        .sheet(item: $sheet) { kind in
            switch kind {
            case .add(let n): AddSourceSheet(animeID: anime.id, number: n)
            case .bulk: BulkAddSheet(animeID: anime.id)
            }
        }
        .fullScreenCover(item: $playing) { item in
            PlayerScreen(
                title: "\(anime.title) — серия \(item.number)",
                url: item.url,
                startAt: library.resumeSeconds(animeID: anime.id, episode: item.number)
            ) { cur, dur in
                library.saveVideo(animeID: anime.id, episode: item.number, seconds: cur, duration: dur)
            }
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            RemoteImage(url: anime.coverURL)
                .frame(width: 110, height: 165)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(anime.title).font(.headline)
                if let t = russianTitle { Text(t).font(.subheadline).foregroundStyle(.secondary) }
                if let year = anime.year { Text(String(year)).font(.subheadline).foregroundStyle(.secondary) }
                if let f = anime.format { Text(f.replacingOccurrences(of: "_", with: " ")).font(.subheadline).foregroundStyle(.secondary) }
                if !anime.statusText.isEmpty { Text(anime.statusText).font(.subheadline).foregroundStyle(.secondary) }
                if let s = anime.score {
                    Label("AniList \(String(format: "%.1f", Double(s) / 10))", systemImage: "star.fill")
                        .font(.subheadline).foregroundStyle(.yellow)
                }
                if let s = ru?.score, s > 0 {
                    Label("Shikimori \(String(format: "%.1f", s))", systemImage: "star.fill")
                        .font(.subheadline).foregroundStyle(.yellow)
                }
                if let e = anime.episodes {
                    Text("Серий: \(e)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var actions: some View {
        HStack {
            if let t = anime.trailerURL {
                Link(destination: t) { Label("Трейлер", systemImage: "play.rectangle") }
                    .buttonStyle(.bordered)
            }
            Button { sheet = .bulk } label: { Label("Добавить ссылки", systemImage: "link.badge.plus") }
                .buttonStyle(.bordered)
        }
    }

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Серии").font(.title3.bold()).padding(.bottom, 8)
            if library.sourceNumbers(animeID: anime.id).isEmpty {
                Text("Видео не входит в каталог: добавьте ссылку (mp4 / m3u8) или файл для каждой серии — например, со своего медиасервера. Нажмите на серию, чтобы добавить источник.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.bottom, 10)
            }
            LazyVStack(spacing: 0) {
                ForEach(1...episodeCount, id: \.self) { n in
                    episodeRow(n)
                    Divider()
                }
            }
        }
    }

    private func episodeRow(_ n: Int) -> some View {
        let source = library.source(animeID: anime.id, number: n)
        let progress = library.progress(animeID: anime.id, episode: n)
        return Button {
            tap(n)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: source == nil ? "plus.circle" : (progress?.watched == true ? "checkmark.circle.fill" : "play.circle.fill"))
                    .font(.title2)
                    .foregroundStyle(source == nil ? Color.secondary : Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Серия \(n)").foregroundStyle(.primary)
                    if let source {
                        Text(source.isLocal ? "Файл на устройстве" : "Ссылка")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let p = progress, !p.watched, p.fraction > 0.01 {
                        ProgressView(value: min(1, p.fraction)).frame(maxWidth: 160)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { sheet = .add(n) } label: { Label(source == nil ? "Добавить источник" : "Изменить источник", systemImage: "pencil") }
            if source != nil {
                Button(role: .destructive) {
                    library.removeSource(animeID: anime.id, number: n)
                } label: { Label("Удалить источник", systemImage: "trash") }
            }
        }
    }

    private func tap(_ n: Int) {
        if let url = library.source(animeID: anime.id, number: n)?.playableURL {
            library.recordAnime(anime, episode: n)
            playing = PlayItem(number: n, url: url)
        } else {
            sheet = .add(n)
        }
    }
}
