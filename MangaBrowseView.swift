import SwiftUI

@MainActor
final class MangaBrowseVM: ObservableObject {
    @Published var items: [Manga] = []
    @Published var loading = false
    @Published var error: String?
    @Published var order: MangaDexService.Order = .popular
    @Published var query = ""

    private var offset = 0
    private var total = Int.max
    private var generation = 0
    private var loadedKey: String?

    func ensureLoaded(language: String) async {
        if loadedKey == key(language), error == nil { return }
        await reload(language: language)
    }

    private func key(_ language: String) -> String { "\(order.rawValue)|\(query)|\(language)" }

    func reload(language: String) async {
        generation += 1
        loadedKey = key(language)
        items = []
        offset = 0
        total = Int.max
        error = nil
        loading = false
        await loadMore(language: language)
    }

    func loadMore(language: String) async {
        guard !loading, offset < total else { return }
        let gen = generation
        loading = true
        do {
            let r = try await MangaDexService.list(search: query, order: order, offset: offset, language: language)
            guard gen == generation else { return }
            let known = Set(items.map(\.id))
            items += r.items.filter { !known.contains($0.id) }
            total = r.total
            offset += max(r.count, 1)
            if r.count == 0 { total = 0 }
            loading = false
        } catch {
            guard gen == generation else { return }
            self.error = error.localizedDescription
            loading = false
        }
    }
}

struct MangaBrowseView: View {
    @StateObject private var vm = MangaBrowseVM()
    @AppStorage("mangaLang") private var lang = "en"

    var body: some View {
        NavigationStack {
            ScrollView {
                Picker("Сортировка", selection: $vm.order) {
                    ForEach(MangaDexService.Order.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                LazyVGrid(columns: posterColumns, spacing: 16) {
                    ForEach(vm.items) { manga in
                        NavigationLink(value: manga) {
                            PosterCard(title: manga.title, cover: manga.coverURL)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if manga.id == vm.items.last?.id { Task { await vm.loadMore(language: lang) } }
                        }
                    }
                }
                .padding()

                if vm.loading { ProgressView().padding() }
                if let e = vm.error {
                    ErrorBanner(message: e) { Task { await vm.reload(language: lang) } }
                }
                if !vm.loading, vm.error == nil, vm.items.isEmpty {
                    Text("Ничего не найдено для выбранного языка перевода.\nЯзык можно сменить в настройках.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding()
                }
            }
            .navigationTitle("Манга")
            .navigationDestination(for: Manga.self) { MangaDetailView(manga: $0) }
            .searchable(text: $vm.query, prompt: "Поиск манги")
            .onSubmit(of: .search) { Task { await vm.reload(language: lang) } }
            .onChange(of: vm.query) { q in
                if q.isEmpty { Task { await vm.ensureLoaded(language: lang) } }
            }
            .onChange(of: vm.order) { _ in Task { await vm.ensureLoaded(language: lang) } }
            .onChange(of: lang) { _ in Task { await vm.ensureLoaded(language: lang) } }
            .task { await vm.ensureLoaded(language: lang) }
        }
    }
}
