import SwiftUI

/// Every achievement by category, earned ones in colour and the rest greyed with how far along they
/// are. A medal opens up close.
struct AchievementsView: View {
    @State private var selected: Achievement?

    private let tracker = AchievementTracker.shared
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40, alignment: .top), count: 6)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 60) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Достижения")
                        .font(.title2.bold())
                    Text("Получено \(tracker.earned.count) из \(Achievement.all.count) за то, что смотрите в REZKA на этом Apple TV.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Achievement.Category.allCases, id: \.self) { category in
                    let items = Achievement.all.filter { $0.category == category }
                    VStack(alignment: .leading, spacing: 30) {
                        HStack(alignment: .firstTextBaseline, spacing: 20) {
                            Text(category.title)
                                .font(.title3.weight(.semibold))
                            Text("\(items.filter { tracker.earned[$0.id] != nil }.count) из \(items.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 50) {
                            ForEach(items) { cell($0) }
                        }
                    }
                    .focusSection()
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .sheet(item: $selected) { achievement in
            MedalDetail(achievement: achievement, isEarned: tracker.earned[achievement.id] != nil)
        }
        .onAppear { tracker.evaluate(announce: true) }
    }

    private func cell(_ achievement: Achievement) -> some View {
        Button {
            selected = achievement
        } label: {
            VStack(spacing: 16) {
                MedalView(medal: achievement.medal, size: 150, isEarned: tracker.earned[achievement.id] != nil)
                Text(achievement.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                AchievementStatus(achievement: achievement)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
        .buttonStyle(RowButtonStyle())
    }
}

/// When it was earned, or how far along a counted one is.
private struct AchievementStatus: View {
    let achievement: Achievement

    private let tracker = AchievementTracker.shared

    var body: some View {
        if let date = tracker.earned[achievement.id] {
            Label(date.formatted(.dateTime.day().month(.wide).year()), systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
        } else if let progress = tracker.progress[achievement.id], progress.target > 1 {
            VStack(spacing: 8) {
                ProgressView(value: Double(min(progress.current, progress.target)), total: Double(progress.target))
                    .frame(width: 180)
                Text("\(min(progress.current, progress.target)) из \(progress.target)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// One medal up close: it turns in as it is shown, as on Apple Watch.
private struct MedalDetail: View {
    let achievement: Achievement
    let isEarned: Bool

    @State private var spin = -200.0

    var body: some View {
        VStack(spacing: 26) {
            MedalView(medal: achievement.medal, size: 360, isEarned: isEarned)
                .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                .padding(.vertical, 20)
                .onAppear {
                    withAnimation(.spring(response: 1.1, dampingFraction: 0.55)) { spin = 0 }
                }
            Text(achievement.category.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(achievement.title)
                .font(.title.bold())
            Text(achievement.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 900)
            AchievementStatus(achievement: achievement)
        }
        .padding(60)
    }
}

extension Achievement: Hashable {
    static func == (lhs: Achievement, rhs: Achievement) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
