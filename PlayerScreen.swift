import SwiftUI
import AVKit

@MainActor
final class PlayerBox: ObservableObject {
    let player = AVPlayer()
    private var token: Any?
    private var onProgress: (@MainActor (Double, Double) -> Void)?

    func start(url: URL, startAt: Double, onProgress: @escaping @MainActor (Double, Double) -> Void) {
        self.onProgress = onProgress
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        if startAt > 5 {
            player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600))
        }
        token = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in self?.report(seconds) }
        }
        player.play()
    }

    private func report(_ seconds: Double) {
        guard seconds > 1 else { return }
        let d = player.currentItem?.duration.seconds ?? 0
        onProgress?(seconds, d.isFinite ? d : 0)
    }

    func stop() {
        report(player.currentTime().seconds)
        if let t = token {
            player.removeTimeObserver(t)
            token = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        onProgress = nil
    }
}

struct PlayerScreen: View {
    let title: String
    let url: URL
    let startAt: Double
    let onProgress: @MainActor (Double, Double) -> Void

    @StateObject private var box = PlayerBox()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: box.player)
                .ignoresSafeArea()
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                Text(title)
                    .font(.footnote.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(radius: 3)
            }
            .padding(.leading, 14)
            .padding(.top, 8)
        }
        .statusBarHidden(true)
        .onAppear { box.start(url: url, startAt: startAt, onProgress: onProgress) }
        .onDisappear { box.stop() }
    }
}
