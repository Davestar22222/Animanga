import Foundation

/// Каталог и чтение манги: официальный публичный API MangaDex.
enum MangaDexService {
    enum Order: String, CaseIterable, Identifiable {
        case popular, latest, rating
        var id: String { rawValue }

        var label: String {
            switch self {
            case .popular: return "Популярное"
            case .latest: return "Новые главы"
            case .rating: return "Рейтинг"
            }
        }

        var param: String {
            switch self {
            case .popular: return "order[followedCount]"
            case .latest: return "order[latestUploadedChapter]"
            case .rating: return "order[rating]"
            }
        }
    }

    private static let base = "https://api.mangadex.org"
    private static let pageSize = 30

    private static func get<T: Decodable>(_ path: String, _ items: [URLQueryItem] = []) async throws -> T {
        var comps = URLComponents(string: base + path)!
        if !items.isEmpty { comps.queryItems = items }
        var req = URLRequest(url: comps.url!)
        req.setValue("AniManga/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AppError.http(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static var ratingItems: [URLQueryItem] {
        [URLQueryItem(name: "contentRating[]", value: "safe"),
         URLQueryItem(name: "contentRating[]", value: "suggestive")]
    }

    // MARK: - Public API

    static func list(search: String?, order: Order, offset: Int, language: String) async throws -> (items: [Manga], total: Int, count: Int) {
        var q: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "includes[]", value: "cover_art"),
            URLQueryItem(name: "availableTranslatedLanguage[]", value: language)
        ]
        q += ratingItems
        if let s = search?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            q.append(URLQueryItem(name: "title", value: s))
            q.append(URLQueryItem(name: "order[relevance]", value: "desc"))
        } else {
            q.append(URLQueryItem(name: order.param, value: "desc"))
        }
        let r: MDList<MDManga> = try await get("/manga", q)
        return (r.data.map { $0.model(coverSize: 256) }, r.total ?? 0, r.data.count)
    }

    static func chapters(mangaID: String, language: String) async throws -> [Chapter] {
        var result: [Chapter] = []
        var seen = Set<String>()
        var offset = 0
        var total = Int.max

        while offset < total {
            var q: [URLQueryItem] = [
                URLQueryItem(name: "limit", value: "500"),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "translatedLanguage[]", value: language),
                URLQueryItem(name: "order[chapter]", value: "asc"),
                URLQueryItem(name: "includeExternalUrl", value: "0")
            ]
            q += ratingItems
            let r: MDList<MDChapter> = try await get("/manga/\(mangaID)/feed", q)
            total = r.total ?? 0
            if r.data.isEmpty { break }
            offset += r.data.count

            for c in r.data {
                let a = c.attributes
                if a.externalUrl != nil || (a.pages ?? 0) == 0 { continue }
                // Несколько переводов одной главы — оставляем первый.
                let key = "\(a.volume ?? "")|\(a.chapter ?? c.id)"
                if !seen.insert(key).inserted { continue }
                result.append(Chapter(id: c.id, number: a.chapter, title: a.title, volume: a.volume, pages: a.pages ?? 0))
            }
        }
        return result
    }

    static func pages(chapterID: String, dataSaver: Bool) async throws -> [URL] {
        let r: AtHome = try await get("/at-home/server/\(chapterID)")
        let files = dataSaver ? r.chapter.dataSaver : r.chapter.data
        let folder = dataSaver ? "data-saver" : "data"
        return files.compactMap { URL(string: "\(r.baseUrl)/\(folder)/\(r.chapter.hash)/\($0)") }
    }

    static func detail(mangaID: String) async throws -> Manga {
        let r: MDSingle<MDManga> = try await get("/manga/\(mangaID)", [URLQueryItem(name: "includes[]", value: "cover_art")])
        return r.data.model(coverSize: 512)
    }

    // MARK: - DTO

    private struct MDList<T: Decodable>: Decodable {
        let data: [T]
        let total: Int?
    }

    private struct MDSingle<T: Decodable>: Decodable {
        let data: T
    }

    private struct MDManga: Decodable {
        struct Attr: Decodable {
            struct Tag: Decodable {
                struct TagAttr: Decodable { let name: [String: String] }
                let attributes: TagAttr
            }
            let title: [String: String]
            let description: [String: String]?
            let status: String?
            let year: Int?
            let tags: [Tag]?
        }
        struct Rel: Decodable {
            struct RelAttr: Decodable { let fileName: String? }
            let id: String
            let type: String
            let attributes: RelAttr?
        }

        let id: String
        let attributes: Attr
        let relationships: [Rel]?

        func model(coverSize: Int) -> Manga {
            var cover: URL?
            if let file = relationships?.first(where: { $0.type == "cover_art" })?.attributes?.fileName {
                cover = URL(string: "https://uploads.mangadex.org/covers/\(id)/\(file).\(coverSize).jpg")
            }
            let title = attributes.title["en"] ?? attributes.title.values.first ?? "Без названия"
            let desc = attributes.description?["en"] ?? attributes.description?.values.first ?? ""
            let tags = (attributes.tags ?? []).compactMap { $0.attributes.name["en"] }
            return Manga(id: id, title: title, coverURL: cover, synopsis: desc,
                         status: attributes.status, year: attributes.year, tags: tags)
        }
    }

    private struct MDChapter: Decodable {
        struct Attr: Decodable {
            let chapter: String?
            let title: String?
            let volume: String?
            let pages: Int?
            let externalUrl: String?
        }
        let id: String
        let attributes: Attr
    }

    private struct AtHome: Decodable {
        struct Ch: Decodable {
            let hash: String
            let data: [String]
            let dataSaver: [String]
        }
        let baseUrl: String
        let chapter: Ch
    }
}
