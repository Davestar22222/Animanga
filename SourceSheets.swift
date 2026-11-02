import SwiftUI
import UniformTypeIdentifiers

struct AddSourceSheet: View {
    let animeID: Int
    let number: Int

    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var importing = false
    @State private var busy = false
    @State private var error: String?

    private var validURL: URL? {
        let t = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: t), let scheme = u.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return u
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ссылка на видео (mp4, m3u8 / HLS)") {
                    TextField("https://…", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Сохранить ссылку") {
                        if let u = validURL {
                            library.setSource(animeID: animeID, EpisodeSource(number: number, urlString: u.absoluteString, localFileName: nil))
                            dismiss()
                        }
                    }
                    .disabled(validURL == nil)
                }

                Section("Или файл с устройства") {
                    Button {
                        importing = true
                    } label: {
                        Label("Выбрать видеофайл", systemImage: "folder")
                    }
                    .disabled(busy)
                    if busy { ProgressView("Копирование…") }
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }

                Section {
                    Text("Плеер поддерживает mp4, mov, m4v и HLS (m3u8). Формат mkv iOS не воспроизводит — перекодируйте его в mp4.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Серия \(number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.movie, .audiovisualContent],
                          allowsMultipleSelection: false) { result in
                handleImport(result)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let e):
            error = e.localizedDescription
        case .success(let urls):
            guard let src = urls.first else { return }
            busy = true
            error = nil
            Task { @MainActor in
                do {
                    let name = try await Task.detached { try LocalVideoStore.importFile(from: src) }.value
                    library.setSource(animeID: animeID, EpisodeSource(number: number, urlString: nil, localFileName: name))
                    busy = false
                    dismiss()
                } catch {
                    self.error = error.localizedDescription
                    busy = false
                }
            }
        }
    }
}

/// Вставка списка ссылок: одна ссылка на строку, нумерация серий подряд.
struct BulkAddSheet: View {
    let animeID: Int

    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var startAt = 1

    private var urls: [URL] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let u = URL(string: t), let s = u.scheme?.lowercased(), s == "http" || s == "https" else { return nil }
            return u
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ссылки — по одной на строку") {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Stepper("Начать с серии \(startAt)", value: $startAt, in: 1...1500)
                    Text("Найдено ссылок: \(urls.count)").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("Добавить") {
                        for (i, u) in urls.enumerated() {
                            library.setSource(animeID: animeID,
                                              EpisodeSource(number: startAt + i, urlString: u.absoluteString, localFileName: nil))
                        }
                        dismiss()
                    }
                    .disabled(urls.isEmpty)
                }
            }
            .navigationTitle("Добавить ссылки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
        }
    }
}
