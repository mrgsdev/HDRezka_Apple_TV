import SwiftUI
import UIKit

/// The banner for a new achievement: the medal turning in at the top of the screen, over the app and
/// over the player, gone in a few seconds. It sits in a window of its own that never takes focus, so
/// the remote keeps working where it was. Several come one after another.
@MainActor
enum AchievementBanner {
    private static var queue: [Achievement] = []
    private static var window: UIWindow?

    static func show(_ achievement: Achievement) {
        queue.append(achievement)
        if window == nil { showNext() }
    }

    private static func showNext() {
        guard !queue.isEmpty,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let achievement = queue.removeFirst()
        let host = UIHostingController(rootView: AchievementBannerView(achievement: achievement))
        host.view.backgroundColor = .clear
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.isUserInteractionEnabled = false
        window.rootViewController = host
        window.alpha = 0
        window.isHidden = false
        self.window = window
        UIView.animate(withDuration: 0.3) { window.alpha = 1 }
        Task {
            try? await Task.sleep(for: .seconds(5))
            UIView.animate(withDuration: 0.4) { window.alpha = 0 } completion: { _ in
                MainActor.assumeIsolated {
                    window.isHidden = true
                    self.window = nil
                    showNext()
                }
            }
        }
    }
}

private struct AchievementBannerView: View {
    let achievement: Achievement

    @State private var spin = -200.0

    var body: some View {
        VStack {
            HStack(spacing: 28) {
                MedalView(medal: achievement.medal, size: 120)
                    .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                    .onAppear {
                        withAnimation(.spring(response: 1.1, dampingFraction: 0.55)) { spin = 0 }
                    }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Новое достижение")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(achievement.title)
                        .font(.title3.bold())
                    Text(achievement.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 560, alignment: .leading)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 26)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 36))
            .overlay(RoundedRectangle(cornerRadius: 36).strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
            .padding(.top, 60)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
