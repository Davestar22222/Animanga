import SwiftUI

@MainActor
final class AnimeBrowseVM: ObservableObject {
    @Published var items: [Anime] = []
    @Published var loading = false
    @Published var error: String?
    @Published var sort: AniListService.Sort = .trending
    @Published var query = ""

    private var page = 1
    private var hasNext = true
    private var generation = 0
    private var loadedKey: String?

    func ensureLoaded() async {
        if loadedKey == "\(sort.rawValue)|\(query)", error == nil { return }
        await reload()
    }

    func reload() async {
        generation += 1
        loadedKey = "\(sort.rawValue)|\(query)"
        items = []
        page = 1
        hasNext = true
        error = nil
        loading = false
        await loadMore()
    }

    func loadMore() async {
        guard !loading, hasNext else { return }
        let gen = generation
        loading = true
        do {
            let r = try await AniListService.fetch(search: query, sort: sort, page: page)
            guard gen == generation else { return }
            let known = Set(items.map(\.id))
            items += r.items.filter { !known.contains($0.id) }
            hasNext = r.hasNext
            page += 1
            loading = false
        } catch {
            guard gen == generation else { return }
            self.error = error.localizedDescription
            loading = false
        }
    }
}

struct AnimeBrowseView: View {
    @StateObject private var vm = AnimeBrowseVM()

    var body: some View {
        NavigationStack {
            ScrollView {
                Picker("Сортировка", selection: $vm.sort) {
                    ForEach(AniListService.Sort.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                LazyVGrid(columns: posterColumns, spacing: 16) {
                    ForEach(vm.items) { anime in
                        NavigationLink(value: anime) {
                            PosterCard(title: anime.title,
                                       cover: anime.coverURL,
                                       badge: anime.score.map { String(format: "%.1f", Double($0) / 10) })
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if anime.id == vm.items.last?.id { Task { await vm.loadMore() } }
                        }
                    }
                }
                .padding()

                if vm.loading { ProgressView().padding() }
                if let e = vm.error {
                    ErrorBanner(message: e) { Task { await vm.reload() } }
                }
            }
            .navigationTitle("Аниме")
            .navigationDestination(for: Anime.self) { AnimeDetailView(anime: $0) }
            .searchable(text: $vm.query, prompt: "Поиск аниме")
            .onSubmit(of: .search) { Task { await vm.reload() } }
            .onChange(of: vm.query) { q in
                if q.isEmpty { Task { await vm.ensureLoaded() } }
            }
            .onChange(of: vm.sort) { _ in Task { await vm.ensureLoaded() } }
            .task { await vm.ensureLoaded() }
        }
    }
}
