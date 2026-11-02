import Foundation

enum MediaKind: String, Codable, Hashable {
    case anime, manga
}

// MARK: - Anime

struct Anime: Identifiable, Hashable, Codable {
    let id: Int
    var title: String
    var coverURL: URL?
    var bannerURL: URL?
    var synopsis: String
    var episodes: Int?
    var status: String?
    var score: Int?
    var genres: [String]
    var year: Int?
    var format: String?
    var trailerURL: URL?
    /// ID на MyAnimeList — он же ID на Shikimori. Опциональный: старое избранное без него декодируется.
    var malID: Int?

    var statusText: String {
        switch status {
        case "FINISHED": return "Завершено"
        case "RELEASING": return "Выходит"
        case "NOT_YET_RELEASED": return "Анонсировано"
        case "CANCELLED": return "Отменено"
        case "HIATUS": return "Перерыв"
        default: return status ?? ""
        }
    }
}

// MARK: - Manga

struct Manga: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var coverURL: URL?
    var synopsis: String
    var status: String?
    var year: Int?
    var tags: [String]

    var statusText: String {
        switch status {
        case "ongoing": return "Выходит"
        case "completed": return "Завершено"
        case "hiatus": return "Перерыв"
        case "cancelled": return "Отменено"
        default: return status ?? ""
        }
    }
}

struct Chapter: Identifiable, Hashable, Codable {
    let id: String
    var number: String?
    var title: String?
    var volume: String?
    var pages: Int

    var displayTitle: String {
        var s = number.map { "Глава \($0)" } ?? "Ваншот"
        if let t = title, !t.isEmpty { s += " — \(t)" }
        return s
    }
}

// MARK: - Episode sources (user's own links / files)

struct EpisodeSource: Codable, Identifiable, Hashable {
    var number: Int
    var urlString: String?
    var localFileName: String?

    var id: Int { number }

    var isLocal: Bool { localFileName != nil }

    var playableURL: URL? {
        if let name = localFileName { return LocalVideoStore.url(for: name) }
        if let s = urlString { return URL(string: s) }
        return nil
    }
}

struct VideoProgress: Codable, Hashable {
    var seconds: Double
    var fraction: Double
    var watched: Bool { fraction > 0.92 }
}

// MARK: - History

struct HistoryEntry: Identifiable, Codable, Hashable {
    var kind: MediaKind
    var anime: Anime?
    var manga: Manga?
    var detail: String
    var date: Date

    var id: String {
        switch kind {
        case .anime: return "a\(anime?.id ?? 0)"
        case .manga: return "m\(manga?.id ?? "")"
        }
    }

    var title: String { anime?.title ?? manga?.title ?? "" }
    var coverURL: URL? { anime?.coverURL ?? manga?.coverURL }
}

// MARK: - Helpers

extension String {
    /// AniList descriptions contain <br> and other tags.
    var strippedHTML: String {
        var s = self.replacingOccurrences(of: "<br>", with: "\n")
        s = s.replacingOccurrences(of: "<br/>", with: "\n")
        s = s.replacingOccurrences(of: "<br />", with: "\n")
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&#039;", with: "'")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Описания Shikimori содержат BBCode: [i]…[/i], [character=1]Имя[/character], [[имя]] и т.п.
    var strippedBBCode: String {
        var s = self.replacingOccurrences(of: "\\[\\[([^\\]]*)\\]\\]", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\[/?[a-zA-Z_]+(=[^\\]]*)?\\]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&#039;", with: "'")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AppError: LocalizedError {
    case http(Int)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .http(let code):
            return code == 429 ? "Слишком много запросов. Подождите немного." : "Ошибка сервера (\(code))."
        case .message(let m):
            return m
        }
    }
}
