import SwiftUI

/// An actor's or a director's page: photo, the site's info table, and a shelf of titles per role.
struct PersonView: View {
    let person: PersonLink

    private enum LoadState {
        case loading
        case loaded(PersonDetails)
        case failed(Error)
    }

    @State private var state = LoadState.loading

    var body: some View {
        ZStack {
            switch state {
            case .loading:
                ProgressView()
            case let .failed(error):
                ErrorStateView(error: error) { await load() }
            case let .loaded(details):
                content(details)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if case .loading = state { await load() }
        }
    }

    private func load() async {
        guard let path = person.path else { return }
        state = .loading
        do {
            state = .loaded(try await RezkaClient.shared.person(path: path))
        } catch where !error.isCancellation {
            state = .failed(error)
            AuthSession.shared.handle(error)
        } catch {}
    }

    private func content(_ details: PersonDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 60) {
                HStack(alignment: .top, spacing: 60) {
                    PosterImage(url: details.photoURL ?? person.photoURL)
                        .frame(width: 300, height: 450)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(radius: 30)

                    VStack(alignment: .leading, spacing: 18) {
                        Text(details.name)
                            .font(.title2.bold())
                        if let original = details.originalName {
                            Text(original)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 12) {
                            ForEach(details.info, id: \.self) { row in
                                GridRow {
                                    Text(row.title)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(row.value)
                                        .font(.callout)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 80)

                if details.careers.isEmpty {
                    Text("На сайте пока нет фильмов и сериалов с этим человеком.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 80)
                }
                ForEach(details.careers) { career in
                    MediaRow(title: [career.title, career.stats].compactMap { $0 }.joined(separator: "  ·  "), items: career.items)
                }
            }
            .padding(.vertical, 50)
        }
    }
}
