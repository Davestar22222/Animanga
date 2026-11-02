import Foundation

/// Русские названия, описания и оценки: публичный API Shikimori (ID совпадает с MyAnimeList).
enum ShikimoriService {
    struct Info: Equatable {
        var russianTitle: String?
        var description: String
        var score: Double?
    }

    private struct DTO: Decodable {
        let russian: String?
        let description: String?
        let score: String?   // приходит строкой, например "8.62"
    }

    private static var cache: [Int: Info] = [:]

    /// nil — если на Shikimori такого тайтла нет.
    static func info(malID: Int) async throws -> Info? {
        if let hit = cache[malID] { return hit }

        var req = URLRequest(url: URL(string: "https://shikimori.one/api/animes/\(malID)")!)
        req.setValue("AniManga/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse {
            if http.statusCode == 404 { return nil }
            if !(200..<300).contains(http.statusCode) { throw AppError.http(http.statusCode) }
        }

        let dto = try JSONDecoder().decode(DTO.self, from: data)
        let info = Info(
            russianTitle: dto.russian.flatMap { $0.isEmpty ? nil : $0 },
            description: (dto.description ?? "").strippedBBCode,
            score: dto.score.flatMap { Double($0) }
        )
        cache[malID] = info
        return info
    }
}
