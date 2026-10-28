import Foundation

/// The site mirror all requests go to. Stored in UserDefaults so it can be changed when a domain gets blocked.
enum Mirror {
    static let fallback = URL(string: "https://rezka.fi/")!
    private static let key = "mirror"

    static var current: URL {
        get {
            UserDefaults.standard.string(forKey: key).flatMap(normalize) ?? fallback
        }
        set {
            let old = current
            UserDefaults.standard.set(newValue.absoluteString, forKey: key)
            CookieVault.migrate(from: old, to: newValue)
        }
    }

    /// Turns user input like `rezka.ag` or `https://rezka.ag/films/` into `https://rezka.ag/`.
    static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let components = URLComponents(string: text), let host = components.host, host.contains(".") else { return nil }
        return URL(string: "\(components.scheme ?? "https")://\(host)/")
    }
}
