import Foundation
import SwiftUI

/// Файлы, импортированные пользователем с устройства (Documents/Videos).
enum LocalVideoStore {
    static var directory: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func importFile(from src: URL) throws -> String {
        let access = src.startAccessingSecurityScopedResource()
        defer { if access { src.stopAccessingSecurityScopedResource() } }
        let ext = src.pathExtension.isEmpty ? "mp4" : src.pathExtension
        let name = UUID().uuidString + "." + ext
        try FileManager.default.copyItem(at: src, to: url(for: name))
        return name
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }
}

/// Избранное, источники серий, прогресс просмотра/чтения и история. Хранится в UserDefaults.
@MainActor
final class LibraryStore: ObservableObject {
    struct State: Codable {
        var favAnime: [Anime] = []
        var favManga: [Manga] = []
        var sources: [String: [EpisodeSource]] = [:]
        var videoProgress: [String: VideoProgress] = [:]
        var readPage: [String: Int] = [:]
        var readChapters: Set<String> = []
        var lastChapter: [String: String] = [:]
        var history: [HistoryEntry] = []
    }

    @Published private(set) var state: State
    private let storageKey = "library.state.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let s = try? JSONDecoder().decode(State.self, from: data) {
            state = s
        } else {
            state = State()
        }
    }

    private func mutate(_ change: (inout State) -> Void) {
        var s = state
        change(&s)
        state = s
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: Favorites

    func isFavorite(_ a: Anime) -> Bool { state.favAnime.contains { $0.id == a.id } }
    func isFavorite(_ m: Manga) -> Bool { state.favManga.contains { $0.id == m.id } }

    func toggleFavorite(_ a: Anime) {
        mutate { s in
            if let i = s.favAnime.firstIndex(where: { $0.id == a.id }) { s.favAnime.remove(at: i) }
            else { s.favAnime.insert(a, at: 0) }
        }
    }

    func toggleFavorite(_ m: Manga) {
        mutate { s in
            if let i = s.favManga.firstIndex(where: { $0.id == m.id }) { s.favManga.remove(at: i) }
            else { s.favManga.insert(m, at: 0) }
        }
    }

    // MARK: Episode sources

    func source(animeID: Int, number: Int) -> EpisodeSource? {
        state.sources[String(animeID)]?.first { $0.number == number }
    }

    func sourceNumbers(animeID: Int) -> [Int] {
        (state.sources[String(animeID)] ?? []).map(\.number)
    }

    func setSource(animeID: Int, _ source: EpisodeSource) {
        mutate { s in
            var list = s.sources[String(animeID)] ?? []
            if let old = list.first(where: { $0.number == source.number }), let f = old.localFileName,
               f != source.localFileName {
                LocalVideoStore.delete(f)
            }
            list.removeAll { $0.number == source.number }
            list.append(source)
            s.sources[String(animeID)] = list
        }
    }

    func removeSource(animeID: Int, number: Int) {
        mutate { s in
            var list = s.sources[String(animeID)] ?? []
            if let old = list.first(where: { $0.number == number }), let f = old.localFileName {
                LocalVideoStore.delete(f)
            }
            list.removeAll { $0.number == number }
            s.sources[String(animeID)] = list
        }
    }

    // MARK: Video progress

    private func videoKey(_ animeID: Int, _ ep: Int) -> String { "\(animeID)-\(ep)" }

    func progress(animeID: Int, episode: Int) -> VideoProgress? {
        state.videoProgress[videoKey(animeID, episode)]
    }

    func resumeSeconds(animeID: Int, episode: Int) -> Double {
        guard let p = progress(animeID: animeID, episode: episode), !p.watched else { return 0 }
        return p.seconds
    }

    func saveVideo(animeID: Int, episode: Int, seconds: Double, duration: Double) {
        guard seconds.isFinite else { return }
        let fraction = duration > 0 ? seconds / duration : 0
        mutate { s in
            s.videoProgress[videoKey(animeID, episode)] = VideoProgress(seconds: seconds, fraction: fraction)
        }
    }

    // MARK: Manga progress

    func readPage(chapterID: String) -> Int { state.readPage[chapterID] ?? 0 }
    func isRead(chapterID: String) -> Bool { state.readChapters.contains(chapterID) }
    func lastChapterID(mangaID: String) -> String? { state.lastChapter[mangaID] }

    func setReadPage(chapterID: String, page: Int) {
        mutate { $0.readPage[chapterID] = page }
    }

    func markRead(chapterID: String) {
        guard !state.readChapters.contains(chapterID) else { return }
        mutate { $0.readChapters.insert(chapterID) }
    }

    // MARK: History

    func recordAnime(_ a: Anime, episode: Int) {
        record(HistoryEntry(kind: .anime, anime: a, manga: nil, detail: "Серия \(episode)", date: Date()))
    }

    func recordManga(_ m: Manga, chapter: Chapter) {
        mutate { $0.lastChapter[m.id] = chapter.id }
        record(HistoryEntry(kind: .manga, anime: nil, manga: m, detail: chapter.displayTitle, date: Date()))
    }

    private func record(_ entry: HistoryEntry) {
        mutate { s in
            s.history.removeAll { $0.id == entry.id }
            s.history.insert(entry, at: 0)
            if s.history.count > 60 { s.history.removeLast(s.history.count - 60) }
        }
    }

    func clearHistory() {
        mutate { $0.history = [] }
    }
}
