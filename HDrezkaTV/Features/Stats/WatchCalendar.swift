import SwiftUI

/// Days of watching as GitHub draws contributions: a column a week, a square a day, the brighter the
/// longer it was watched, today outlined.
struct WatchCalendar: View {
    /// The days to draw, e.g. a year.
    let interval: DateInterval
    /// Seconds watched by the start of each day.
    let seconds: [Date: Double]

    private let calendar = Calendar.current
    /// Up to half an hour, an hour and a half, three hours, more.
    private static let levels: [Double] = [30 * 60, 90 * 60, 3 * 3600]
    private static let spacing: CGFloat = 6
    private static let largestCell: CGFloat = 40

    var body: some View {
        let weeks = weeks()
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                Text("Календарь просмотров")
                    .font(.headline)
                Spacer()
                legend
            }
            GeometryReader { proxy in
                let labelWidth: CGFloat = 60
                let cell = min(Self.largestCell, max(14, (proxy.size.width - labelWidth) / CGFloat(max(weeks.count, 1)) - Self.spacing))
                HStack(alignment: .top, spacing: Self.spacing) {
                    weekdayLabels(cell: cell)
                        .frame(width: labelWidth - Self.spacing, alignment: .leading)
                    ForEach(weeks.indices, id: \.self) { index in
                        VStack(spacing: Self.spacing) {
                            monthLabel(for: weeks[index], cell: cell)
                            ForEach(0..<7, id: \.self) { row in
                                square(weeks[index][row], cell: cell)
                            }
                        }
                    }
                }
            }
            .frame(height: 7 * Self.largestCell + 6 * Self.spacing + 36)
            footer
        }
    }

    // MARK: Grid

    /// Whole weeks from the one the interval starts in; days outside it are nil.
    private func weeks() -> [[Date?]] {
        guard var day = calendar.dateInterval(of: .weekOfYear, for: interval.start)?.start else { return [] }
        var weeks: [[Date?]] = []
        while day < interval.end {
            var week: [Date?] = []
            for _ in 0..<7 {
                week.append(interval.contains(day) && day < interval.end ? day : nil)
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? interval.end
            }
            weeks.append(week)
        }
        return weeks
    }

    private func weekdayLabels(cell: CGFloat) -> some View {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return VStack(alignment: .leading, spacing: Self.spacing) {
            Color.clear.frame(height: 30)
            ForEach(0..<7, id: \.self) { row in
                // Every other day, as GitHub does, so the labels don't crowd.
                Text(verbatim: row.isMultiple(of: 2) ? symbols[(first + row) % 7] : "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: cell)
            }
        }
    }

    /// The month's name over the week its first day falls in.
    private func monthLabel(for week: [Date?], cell: CGFloat) -> some View {
        let first = week.compactMap { $0 }.first { calendar.component(.day, from: $0) == 1 }
            ?? (week.compactMap { $0 }.first == interval.start ? interval.start : nil)
        return Text(verbatim: first.map { $0.formatted(.dateTime.month(.abbreviated)) } ?? "")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize()
            .frame(width: cell, height: 30, alignment: .leading)
    }

    @ViewBuilder
    private func square(_ day: Date?, cell: CGFloat) -> some View {
        if let day {
            RoundedRectangle(cornerRadius: cell * 0.22)
                .fill(Self.color(for: seconds[day] ?? 0))
                .overlay {
                    if calendar.isDateInToday(day) {
                        RoundedRectangle(cornerRadius: cell * 0.22).strokeBorder(.primary.opacity(0.7), lineWidth: 2)
                    }
                }
                .frame(width: cell, height: cell)
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }

    private static func color(for seconds: Double) -> Color {
        guard seconds >= 60 else { return Color.primary.opacity(0.08) }
        let level = levels.firstIndex { seconds <= $0 } ?? levels.count
        return Color.accentColor.opacity([0.3, 0.55, 0.8, 1][level])
    }

    // MARK: Footer

    private var footer: some View {
        let days = seconds.filter { $0.value >= 60 && interval.contains($0.key) }
        let longest = days.max { $0.value < $1.value }
        return HStack(alignment: .firstTextBaseline, spacing: 36) {
            Text("Дней с просмотром: \(days.count)")
            Text("Дней подряд, самое большее: \(longestStreak(Set(days.keys)))")
            if let longest {
                Text("Самый долгий день: \(longest.key.formatted(.dateTime.day().month(.wide))), \(StatsView.hours(longest.value))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var legend: some View {
        HStack(spacing: 8) {
            Text("Меньше")
            ForEach([0, 20 * 60, 60 * 60, 2 * 3600, 4 * 3600] as [Double], id: \.self) { seconds in
                RoundedRectangle(cornerRadius: 5)
                    .fill(Self.color(for: seconds))
                    .frame(width: 22, height: 22)
            }
            Text("Больше")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize()
    }

    private func longestStreak(_ days: Set<Date>) -> Int {
        var best = 0
        for day in days {
            guard let before = calendar.date(byAdding: .day, value: -1, to: day), !days.contains(before) else { continue }
            var length = 1
            var next = day
            while let following = calendar.date(byAdding: .day, value: 1, to: next), days.contains(following) {
                length += 1
                next = following
            }
            best = max(best, length)
        }
        return best
    }
}
