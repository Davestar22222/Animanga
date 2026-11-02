import SwiftUI

struct ReaderView: View {
    let manga: Manga
    let chapters: [Chapter]

    @State private var index: Int
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("readerMode") private var mode = "paged"      // paged | webtoon
    @AppStorage("readerRTL") private var rtl = false
    @AppStorage("dataSaver") private var dataSaver = false

    @State private var pages: [URL] = []
    @State private var page = 0
    @State private var loading = false
    @State private var error: String?
    @State private var chrome = true

    init(manga: Manga, chapters: [Chapter], startIndex: Int) {
        self.manga = manga
        self.chapters = chapters
        _index = State(initialValue: startIndex)
    }

    private var chapter: Chapter? { chapters.indices.contains(index) ? chapters[index] : nil }
    private var hasNext: Bool { index + 1 < chapters.count }
    private var hasPrev: Bool { index > 0 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if loading {
                ProgressView().tint(.white)
            } else if let error {
                VStack(spacing: 12) {
                    Text(error).foregroundStyle(.white).multilineTextAlignment(.center)
                    Button("Повторить") { Task { await load() } }.buttonStyle(.bordered)
                }
                .padding()
            } else if mode == "webtoon" {
                webtoon
            } else {
                paged
            }
        }
        .overlay(alignment: .top) { if chrome { topBar } }
        .overlay(alignment: .bottom) { if chrome { bottomBar } }
        .statusBarHidden(!chrome)
        .task(id: index) { await load() }
        .onChange(of: page) { p in
            guard let ch = chapter, !pages.isEmpty else { return }
            let clamped = min(p, pages.count - 1)
            library.setReadPage(chapterID: ch.id, page: clamped)
            if clamped >= pages.count - 2 { library.markRead(chapterID: ch.id) }
        }
    }

    // MARK: Modes

    private var webtoon: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(pages.indices, id: \.self) { i in
                    PageImage(url: pages[i])
                        .onAppear { page = i }
                }
                endView.frame(height: 260)
            }
        }
        .onTapGesture { withAnimation { chrome.toggle() } }
        .ignoresSafeArea(edges: .horizontal)
    }

    private var paged: some View {
        let ids: [Int] = rtl ? [pages.count] + Array(pages.indices.reversed()) : Array(pages.indices) + [pages.count]
        return TabView(selection: $page) {
            ForEach(ids, id: \.self) { i in
                Group {
                    if i < pages.count {
                        ZoomablePage(url: pages[i]) { withAnimation { chrome.toggle() } }
                    } else {
                        endView
                    }
                }
                .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
    }

    private var endView: some View {
        VStack(spacing: 14) {
            Text("Конец главы").font(.headline).foregroundStyle(.white)
            if hasNext {
                Button {
                    index += 1
                } label: {
                    Label("Следующая глава", systemImage: "chevron.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Это последняя доступная глава").font(.footnote).foregroundStyle(.gray)
            }
            Button("Закрыть") { dismiss() }.buttonStyle(.bordered)
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Text(chapter?.displayTitle ?? "")
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Menu {
                Picker("Режим", selection: $mode) {
                    Text("Постранично").tag("paged")
                    Text("Лента (вебтун)").tag("webtoon")
                }
                Toggle("Справа налево (манга)", isOn: $rtl)
            } label: {
                Image(systemName: "slider.horizontal.3").font(.headline).padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .tint(.white)
    }

    private var bottomBar: some View {
        HStack {
            Button { index -= 1 } label: { Image(systemName: "chevron.left") }
                .disabled(!hasPrev)
            Spacer()
            if !pages.isEmpty {
                Text("\(min(page + 1, pages.count)) / \(pages.count)")
                    .font(.footnote.monospacedDigit())
            }
            Spacer()
            Button { index += 1 } label: { Image(systemName: "chevron.right") }
                .disabled(!hasNext)
        }
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .tint(.white)
    }

    // MARK: Loading

    private func load() async {
        guard let ch = chapter else { return }
        loading = true
        error = nil
        pages = []
        do {
            let urls = try await MangaDexService.pages(chapterID: ch.id, dataSaver: dataSaver)
            if Task.isCancelled { return }
            pages = urls
            page = min(library.readPage(chapterID: ch.id), max(0, urls.count - 1))
            library.recordManga(manga, chapter: ch)
            if urls.isEmpty { error = "В этой главе нет страниц." }
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            self.error = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Page views

struct PageImage: View {
    let url: URL
    @State private var attempt = 0

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .failure:
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.yellow)
                    Button("Загрузить снова") { attempt += 1 }.buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            default:
                ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 300)
            }
        }
        .id(attempt)
    }
}

/// Страница с зумом по двойному тапу и прокруткой в увеличенном состоянии.
struct ZoomablePage: View {
    let url: URL
    var onTap: () -> Void
    @State private var zoom: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                PageImage(url: url)
                    .frame(width: geo.size.width * zoom, height: geo.size.height * zoom)
            }
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) { zoom = zoom > 1 ? 1 : 2.5 }
            }
            .onTapGesture { onTap() }
        }
    }
}
