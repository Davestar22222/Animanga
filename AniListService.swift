import Foundation

/// Каталог аниме: официальный публичный GraphQL API AniList (метаданные, обложки, трейлеры).
enum AniListService {
    enum Sort: String, CaseIterable, Identifiable {
        case trending, popular, top, airing
        var id: String { rawValue }

        var label: String {
            switch self {
            case .trending: return "В тренде"
            case .popular: return "Популярное"
            case .top: return "Топ"
            case .airing: return "Онгоинги"
            }
        }

        var sortValue: String {
            switch self {
            case .trending: return "TRENDING_DESC"
            case .popular: return "POPULARITY_DESC"
            case .top: return "SCORE_DESC"
            case .airing: return "POPULARITY_DESC"
            }
        }

        var status: String? { self == .airing ? "RELEASING" : nil }
    }

    private static let query = """
    query ($page: Int, $search: String, $sort: [MediaSort], $status: MediaStatus) {
      Page(page: $page, perPage: 30) {
        pageInfo { hasNextPage }
        media(type: ANIME, search: $search, sort: $sort, status: $status, isAdult: false) {
          id
          idMal
          title { romaji english }
          coverImage { large extraLarge }
          bannerImage
          description(asHtml: false)
          episodes
          status
          averageScore
          genres
          seasonYear
          format
          trailer { id site }
        }
      }
    }
    """

    static func fetch(search: String?, sort: Sort, page: Int) async throws -> (items: [Anime], hasNext: Bool) {
        var variables: [String: Any] = ["page": page, "sort": [sort.sortValue]]
        if let status = sort.status { variables["status"] = status }
        if let s = search?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            variables["search"] = s
            variables["sort"] = ["SEARCH_MATCH"]
            variables.removeValue(forKey: "status")
        }

        var req = URLRequest(url: URL(string: "https://graphql.anilist.co")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AppError.http(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(GQLResponse.self, from: data)
        if let msg = decoded.errors?.first?.message { throw AppError.message(msg) }
        guard let pageData = decoded.data?.Page else { throw AppError.message("Пустой ответ сервера") }
        return (pageData.media.map(\.model), pageData.pageInfo.hasNextPage)
    }

    // MARK: - DTO

    private struct GQLResponse: Decodable {
        let data: DataBox?
        let errors: [GQLError]?
    }
    private struct GQLError: Decodable { let message: String }
    private struct DataBox: Decodable { let Page: PageBox }
    private struct PageBox: Decodable {
        let pageInfo: PageInfo
        let media: [Media]
    }
    private struct PageInfo: Decodable { let hasNextPage: Bool }

    private struct Media: Decodable {
        struct Title: Decodable { let romaji: String?; let english: String? }
        struct Cover: Decodable { let large: String?; let extraLarge: String? }
        struct Trailer: Decodable { let id: String?; let site: String? }

        let id: Int
        let idMal: Int?
        let title: Title
        let coverImage: Cover?
        let bannerImage: String?
        let description: String?
        let episodes: Int?
        let status: String?
        let averageScore: Int?
        let genres: [String]?
        let seasonYear: Int?
        let format: String?
        let trailer: Trailer?

        var model: Anime {
            var trailerURL: URL?
            if let t = trailer, t.site == "youtube", let tid = t.id {
                trailerURL = URL(string: "https://www.youtube.com/watch?v=\(tid)")
            }
            return Anime(
                id: id,
                title: title.english ?? title.romaji ?? "Без названия",
                coverURL: (coverImage?.extraLarge ?? coverImage?.large).flatMap(URL.init(string:)),
                bannerURL: bannerImage.flatMap(URL.init(string:)),
                synopsis: (description ?? "").strippedHTML,
                episodes: episodes,
                status: status,
                score: averageScore,
                genres: genres ?? [],
                year: seasonYear,
                format: format,
                trailerURL: trailerURL,
                malID: idMal
            )
        }
    }
}
