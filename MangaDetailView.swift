import SwiftUI

struct MangaDetailView: View {
    let manga: Manga

    @EnvironmentObject private var library: LibraryStore
    @AppStorage("mangaLang") private var lang = "en"
    @State private var chapters: [Chapter] = []
    @State private var loading = false
    @State private var error: String?
    @State private var descending = false
    @State private var reading: ReadItem?

    struct ReadItem: Identifiable {
        let id = UUID()
        let index: Int
    }

    private var rows: [(offset: Int, element: Chapter)] {
        let all = Array(chapters.enumerated()).map { (offset: $0.offset, element: $0.element) }
        return descending ? all.reversed() : all
    }

    private var continueIndex: Int? {
        guard let id = library.lastChapterID(mangaID: manga.id) else { return nil }
        return chapters.firstIndex { $0.id == id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    RemoteImage(url: manga.coverURL)
                        .frame(width: 110, height: 165)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(manga.title).font(.headline)
                        if let y = manga.year { Text(String(y)).font(.subheadline).foregroundStyle(.secondary) }
                        if !manga.statusText.isEmpty { Text(manga.statusText).font(.subheadline).foregroundStyle(.secondary) }
                        if !chapters.isEmpty { Text("Глав: \(chapters.count)").font(.subheadline).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                }

                HStack {
                    if let i = continueIndex {
                        Button { reading = ReadItem(index: i) } label: { Label("Продолжить", systemImage: "book.fill") }
                            .buttonStyle(.borderedProminent)
                    } else if !chapters.isEmpty {
                        Button { reading = ReadItem(index: 0) } label: { Label("Читать с начала", systemImage: "book.fill") }
                            .buttonStyle(.borderedProminent)
                    }
                }

                ExpandableText(text: manga.synopsis)

                if !manga.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(manga.tags, id: \.self) { Chip(text: $0) } }
                    }
                }

                Divider()
                HStack {
                    Text("Главы").font(.title3.bold())
                    Spacer()
                    Button {
                        descending.toggle()
                    } label: {
                        Label(descending ? "Сначала новые" : "Сначала старые", systemImage: "arrow.up.arrow.down")
                            .font(.footnote)
                    }
                }

                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let error { ErrorBanner(message: error) { Task { await load() } } }
                if !loading, error == nil, chapters.isEmpty {
                    Text("Глав на выбранном языке нет. Язык можно сменить в настройках.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                LazyVStack(spacing: 0) {
                    ForEach(rows, id: \.element.id) { row in
                        Button {
                            reading = ReadItem(index: row.offset)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.element.displayTitle)
                                        .foregroundStyle(library.isRead(chapterID: row.element.id) ? .secondary : .primary)
                                        .multilineTextAlignment(.leading)
                                    if let v = row.element.volume {
                                        Text("Том \(v)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if library.isRead(chapterID: row.element.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            .padding()
        }
        .navigationTitle(manga.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    library.toggleFavorite(manga)
                } label: {
                    Image(systemName: library.isFavorite(manga) ? "heart.fill" : "heart")
                }
            }
        }
        .task(id: lang) { await load() }
        .fullScreenCover(item: $reading) { item in
            ReaderView(manga: manga, chapters: chapters, startIndex: item.index)
        }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            let result = try await MangaDexService.chapters(mangaID: manga.id, language: lang)
            if Task.isCancelled { return }
            chapters = result
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            self.error = error.localizedDescription
        }
        loading = false
    }
}
