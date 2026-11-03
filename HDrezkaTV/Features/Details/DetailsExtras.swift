import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: Rating

/// The site's rating as ten stars filled to the average, with the votes and this Apple TV's own vote.
struct SiteRatingRow: View {
    let rating: SiteRating
    let myRating: Int?
    let isRating: Bool

    var body: some View {
        HStack(spacing: 20) {
            stars
            Text(rating.value.formatted(.number.precision(.fractionLength(2))))
                .font(.headline.monospacedDigit())
            Text("\(rating.votes.formatted()) \(Self.votesWord(rating.votes))")
                .foregroundStyle(.secondary)
            if isRating {
                ProgressView()
            } else if let myRating {
                Label("Ваша оценка: \(myRating)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if !rating.canVote {
                Label("Вы уже оценили", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private var row: some View {
        HStack(spacing: 4) {
            ForEach(1...10, id: \.self) { _ in Image(systemName: "star.fill") }
        }
        .font(.system(size: 24))
    }

    private var stars: some View {
        row
            .foregroundStyle(Color.primary.opacity(0.18))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Brand.gold)
                        .frame(width: proxy.size.width * CGFloat(min(max(rating.value, 0), 10)) / 10)
                }
                .mask(row)
            }
    }

    /// Russian has three plural forms and English two; the number is formatted separately, with grouping.
    private static func votesWord(_ count: Int) -> String {
        guard Bundle.main.preferredLocalizations.first == "ru" else {
            return count == 1 ? String(localized: "голос") : String(localized: "голосов")
        }
        let tens = count % 100, ones = count % 10
        if (11...14).contains(tens) { return String(localized: "голосов") }
        switch ones {
        case 1: return String(localized: "голос")
        case 2...4: return String(localized: "голоса")
        default: return String(localized: "голосов")
        }
    }
}

/// A score from 1 to 10, asked once more before it goes: the site takes one vote per account and never
/// lets it be changed.
struct RatingSheet: View {
    let title: String
    let rate: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Int?

    var body: some View {
        VStack(spacing: 50) {
            if let chosen {
                Text("Оценить «\(title)» на \(chosen)?")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Сайт принимает один голос и не даёт его изменить.")
                    .foregroundStyle(.secondary)
                // «Отмена» first, where the focus lands: a second press by habit must not send the vote.
                HStack(spacing: 30) {
                    Button("Отмена") { self.chosen = nil }
                    Button("Оценить") {
                        rate(chosen)
                        dismiss()
                    }
                }
            } else {
                Text("Ваша оценка")
                    .font(.title2.bold())
                HStack(spacing: 16) {
                    ForEach(1...10, id: \.self) { score in
                        Button {
                            chosen = score
                        } label: {
                            Text(verbatim: "\(score)")
                                .font(.title3.weight(.semibold))
                                .frame(width: 60)
                        }
                    }
                }
                Text("Как на сайте: от 1 до 10.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(60)
        .animation(.easeOut(duration: 0.2), value: chosen)
    }
}

// MARK: Dub popularity

/// "Не можешь выбрать озвучку?" from the site: the share of viewers each dub has; a row picks that dub.
struct DubPopularitySheet: View {
    let popularity: DubPopularity
    let translators: [Translator]
    let current: Translator?
    let select: (Translator) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text(popularity.title)
                .font(.title2.bold())
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(popularity.entries) { row($0) }
                }
                .padding(20)
            }
            if !popularity.note.isEmpty {
                Text(popularity.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(60)
        .frame(width: 1200)
    }

    private func row(_ entry: DubPopularity.Entry) -> some View {
        let translator = translators.first { $0.name == entry.name }
        let isCurrent = translator != nil && translator == current
        return Button {
            guard let translator else { return }
            select(translator)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Text(entry.name)
                    .fontWeight(isCurrent ? .bold : .medium)
                    .lineLimit(1)
                if isCurrent {
                    Image(systemName: "checkmark")
                } else if translator?.isPremium == true {
                    Image(systemName: "crown.fill").foregroundStyle(.orange)
                }
                Spacer(minLength: 20)
                // "42,59%" as on the site.
                Text(entry.percent.formatted(.number.precision(.fractionLength(0...2))) + "%")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(alignment: .leading) {
                GeometryReader { proxy in
                    Color.accentColor.opacity(0.35)
                        .frame(width: proxy.size.width * min(max(entry.percent, 0), 100) / 100)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(RowButtonStyle())
        .disabled(translator == nil)
    }
}

// MARK: Trailer

/// The trailer's YouTube page as a QR code, for a phone's camera: Apple TV has no browser, and the
/// YouTube app is not here.
struct TrailerCodeView: View {
    let page: URL

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 40) {
            Text("Трейлер на YouTube")
                .font(.title2.bold())
            if let code = Self.code(for: page) {
                Image(uiImage: code)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 420, height: 420)
                    .padding(24)
                    .background(.white, in: RoundedRectangle(cornerRadius: 24))
            }
            Text("Наведите камеру телефона на код, чтобы открыть трейлер. На Apple TV с приложением YouTube он откроется сразу.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 900)
            Text(verbatim: page.absoluteString)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Button("Готово") { dismiss() }
        }
        .padding(60)
        .frame(width: 1100)
    }

    private static func code(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}

// MARK: People

/// A director or an actor: the photo in a circle and the name, opening their page.
struct PersonCard: View {
    let person: PersonLink
    var role: String?

    var body: some View {
        VStack(spacing: 16) {
            NavigationLink(value: person) {
                PersonPhoto(url: person.photoURL)
                    .frame(width: 170, height: 170)
            }
            .buttonStyle(.card)
            .clipShape(Circle())
            .disabled(person.path == nil)
            VStack(spacing: 4) {
                Text(person.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let role {
                    Text(role)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 200)
        }
    }
}

/// A round photo of a person, or a silhouette when the site has none.
struct PersonPhoto: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                PosterImage(url: url)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(Circle())
    }
}
