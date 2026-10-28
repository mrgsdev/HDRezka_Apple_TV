import Foundation
import Network

/// A tiny HTTP server on the local network so the user can type the HDrezka login on a phone
/// instead of the TV keyboard. Only the path with the one-time token is accepted.
/// Listener state is only touched on `queue`.
final class PhoneLoginServer: @unchecked Sendable {
    /// Returns an error message to show on the phone, or nil on success.
    typealias SubmitHandler = @MainActor (_ email: String, _ password: String) async -> String?

    let token: String
    var onReady: (@MainActor (UInt16) -> Void)?

    private let onSubmit: SubmitHandler
    private let queue = DispatchQueue(label: "PhoneLoginServer")
    private var listener: NWListener?
    private static let preferredPort: UInt16 = 8765

    init(onSubmit: @escaping SubmitHandler) {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        token = String((0..<6).map { _ in alphabet.randomElement()! })
        self.onSubmit = onSubmit
    }

    func start() {
        queue.async { self.listen(on: NWEndpoint.Port(rawValue: Self.preferredPort) ?? .any) }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
        }
    }

    private func listen(on port: NWEndpoint.Port) {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters, on: port) else {
            if port != .any { listen(on: .any) }
            return
        }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener else { return }
            switch state {
            case .ready:
                if let port = listener.port?.rawValue {
                    Task { @MainActor in self.onReady?(port) }
                }
            case .failed:
                listener.cancel()
                if port != .any { self.listen(on: .any) }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    // MARK: HTTP

    private struct Request {
        let method: String
        let path: String
        let body: Data
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                self.route(request, on: connection)
            } else if isComplete || error != nil || buffer.count > 256 * 1024 {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private static func parse(_ data: Data) -> Request? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let start = lines.first?.split(separator: " ") ?? []
        guard start.count >= 2 else { return nil }

        let length = lines.dropFirst().compactMap { line -> Int? in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].lowercased() == "content-length" else { return nil }
            return Int(parts[1].trimmingCharacters(in: .whitespaces))
        }.first ?? 0

        let body = data[headerEnd.upperBound...]
        guard body.count >= length else { return nil }
        let path = String(start[1]).components(separatedBy: "?")[0]
        return Request(method: String(start[0]), path: path, body: Data(body.prefix(length)))
    }

    private func route(_ request: Request, on connection: NWConnection) {
        guard request.path == "/\(token)" else {
            return send(Self.page(Self.messageCard(title: "Ссылка устарела", text: "Откройте адрес, который сейчас показан на экране Apple TV.")),
                        status: "404 Not Found", on: connection)
        }
        guard request.method == "POST" else {
            return send(Self.page(formHTML(error: nil)), on: connection)
        }

        let form = Self.decodeForm(request.body)
        let email = form["email"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = form["password"] ?? ""
        guard !email.isEmpty, !password.isEmpty else {
            return send(Self.page(formHTML(error: "Введите email и пароль.")), on: connection)
        }

        Task { @MainActor in
            let error = await self.onSubmit(email, password)
            let html = error.map { Self.page(self.formHTML(error: $0, email: email)) }
                ?? Self.page(Self.messageCard(title: "Готово ✓", text: "Вход выполнен — на телевизоре уже открывается главная. Эту страницу можно закрыть."))
            self.queue.async { self.send(html, on: connection) }
        }
    }

    private func send(_ html: String, status: String = "200 OK", on connection: NWConnection) {
        let body = Data(html.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func decodeForm(_ body: Data) -> [String: String] {
        var result: [String: String] = [:]
        for pair in String(decoding: body, as: UTF8.self).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0)
            }
            if let key = parts.first { result[key] = parts.count > 1 ? parts[1] : "" }
        }
        return result
    }

    // MARK: Pages

    private func formHTML(error: String?, email: String = "") -> String {
        let host = Self.escape(Mirror.current.host() ?? "HDrezka")
        let errorBlock = error.map { "<div class=\"err\">\(Self.escape($0))</div>" } ?? ""
        return """
        <form method="post" action="/\(token)" onsubmit="var b=this.querySelector('button');b.disabled=true;b.textContent='Входим, подождите…';">
          <h1>Вход на Apple TV</h1>
          <p>Логин и пароль от аккаунта HDrezka уйдут на телевизор по локальной сети, а с него — на сайт \(host).</p>
          <label for="e">Email</label>
          <input id="e" name="email" type="email" autocomplete="username" autocapitalize="off" value="\(Self.escape(email))" required autofocus>
          <label for="p">Пароль</label>
          <input id="p" name="password" type="password" autocomplete="current-password" required>
          <button type="submit">Войти на телевизоре</button>
          \(errorBlock)
        </form>
        """
    }

    private static func messageCard(title: String, text: String) -> String {
        "<div class=\"card\"><h1>\(escape(title))</h1><p>\(escape(text))</p></div>"
    }

    private static func page(_ content: String) -> String {
        """
        <!doctype html>
        <html lang="ru"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>HDrezka TV — вход</title>
        <style>
          :root { color-scheme: dark; }
          * { box-sizing: border-box; }
          body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 16px;
                 font-family: -apple-system, system-ui, sans-serif; color: #fff;
                 background: linear-gradient(135deg, #2a0d38, #000 55%, #08222a); }
          form, .card { width: 100%; max-width: 400px; padding: 28px; border-radius: 20px;
                        background: rgba(255,255,255,.06); border: 1px solid rgba(255,255,255,.12); }
          h1 { margin: 0 0 8px; font-size: 24px; }
          p { margin: 0 0 18px; color: #aaa; font-size: 15px; line-height: 1.45; }
          label { display: block; margin: 14px 0 6px; font-size: 13px; color: #bbb; }
          input { width: 100%; padding: 13px 14px; font-size: 17px; color: #fff; background: #111;
                  border: 1px solid #444; border-radius: 12px; }
          button { width: 100%; margin-top: 22px; padding: 14px; font-size: 17px; font-weight: 600; color: #fff;
                   border: 0; border-radius: 12px; background: linear-gradient(90deg, #c82dde, #3a92a6); }
          button:disabled { opacity: .6; }
          .err { margin-top: 14px; color: #ff6b81; font-size: 15px; }
        </style></head>
        <body>\(content)</body></html>
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
