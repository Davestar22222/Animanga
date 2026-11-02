import SwiftUI

struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
                ZStack {
                    Color.gray.opacity(0.2)
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            default:
                ZStack {
                    Color.gray.opacity(0.15)
                    ProgressView()
                }
            }
        }
    }
}

struct PosterCard: View {
    let title: String
    let cover: URL?
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.gray.opacity(0.15)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay { RemoteImage(url: cover) }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(6)
                    }
                }
            Text(title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
        }
    }
}

struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.gray.opacity(0.2), in: Capsule())
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark").font(.title)
            Text(message).font(.footnote).multilineTextAlignment(.center)
            if let retry {
                Button("Повторить", action: retry).buttonStyle(.bordered)
            }
        }
        .foregroundStyle(.secondary)
        .padding()
    }
}

struct ExpandableText: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        if text.isEmpty {
            Text("Описание отсутствует").foregroundStyle(.secondary).font(.subheadline)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.subheadline)
                    .lineLimit(expanded ? nil : 5)
                Button(expanded ? "Свернуть" : "Подробнее") {
                    withAnimation { expanded.toggle() }
                }
                .font(.footnote.bold())
            }
        }
    }
}

let posterColumns = [GridItem(.adaptive(minimum: 110, maximum: 180), spacing: 12)]
