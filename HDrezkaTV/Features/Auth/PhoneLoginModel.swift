import CoreImage.CIFilterBuiltins
import Foundation
import Observation
import UIKit

/// Runs `PhoneLoginServer` while the login screen is visible and exposes its address as a QR code.
@MainActor
@Observable
final class PhoneLoginModel {
    private(set) var url: URL?
    private(set) var qrCode: UIImage?
    private(set) var status: String?

    private var server: PhoneLoginServer?

    func start() {
        guard server == nil else { return }
        let server = PhoneLoginServer { [weak self] email, password in
            // signIn returns nil on success, so `self?.signIn(...) ?? message` would turn success into an error.
            guard let self else { return "Экран входа на телевизоре уже закрыт." }
            return await self.signIn(email: email, password: password)
        }
        server.onReady = { [weak self, weak server] port in
            guard let self, let server, let ip = Self.localIPv4() else { return }
            let url = URL(string: "http://\(ip):\(port)/\(server.token)")
            self.url = url
            self.qrCode = url.flatMap { Self.qrImage(for: $0.absoluteString) }
        }
        server.start()
        self.server = server
    }

    func stop() {
        server?.stop()
        server = nil
        url = nil
        qrCode = nil
    }

    private func signIn(email: String, password: String) async -> String? {
        status = "Входим с телефона…"
        do {
            try await AuthSession.shared.login(email: email, password: password)
            status = nil
            return nil
        } catch {
            status = error.localizedDescription
            return error.localizedDescription
        }
    }

    private static func qrImage(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }

    /// The device's IPv4 address on Wi-Fi/Ethernet (en*), so a phone on the same network can reach it.
    private static func localIPv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }

        var candidates: [(name: String, ip: String)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if !ip.hasPrefix("169.254.") {
                candidates.append((String(cString: entry.ifa_name), ip))
            }
        }
        return candidates.first { $0.name == "en0" }?.ip
            ?? candidates.first { $0.name.hasPrefix("en") }?.ip
            ?? candidates.first?.ip
    }
}
