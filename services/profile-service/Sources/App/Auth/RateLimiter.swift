import Foundation
import NIOCore
import Vapor

actor RateLimiter {
    let limit: Int
    let window: TimeInterval
    let maximumTrackedKeys: Int
    private let now: @Sendable () -> Date
    private var windows: [String: (start: Date, count: Int)] = [:]
    private var lastSweep = Date.distantPast

    init(limit: Int, window: TimeInterval, maximumTrackedKeys: Int = 10_000, now: @escaping @Sendable () -> Date = { Date() }) {
        self.limit = limit
        self.window = window
        self.maximumTrackedKeys = maximumTrackedKeys
        self.now = now
    }

    func acquire(_ key: String) -> TimeInterval? {
        let current = now()
        if windows.count >= maximumTrackedKeys, current.timeIntervalSince(lastSweep) >= window {
            windows = windows.filter { current.timeIntervalSince($0.value.start) < window }
            lastSweep = current
        }
        guard let entry = windows[key], current.timeIntervalSince(entry.start) < window else {
            if windows[key] == nil, windows.count >= maximumTrackedKeys {
                let unblocked = windows.filter { $0.value.count < limit }
                let candidates = unblocked.isEmpty ? windows : unblocked
                if let oldest = candidates.min(by: { $0.value.start < $1.value.start })?.key {
                    windows[oldest] = nil
                }
            }
            windows[key] = (current, 1)
            return nil
        }
        guard entry.count < limit else {
            return window - current.timeIntervalSince(entry.start)
        }
        windows[key] = (entry.start, entry.count + 1)
        return nil
    }
}

struct RateLimitMiddleware: AsyncMiddleware {
    let limiter: RateLimiter

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let route = request.route.map { $0.path.map(\.description).joined(separator: "/") } ?? request.url.path
        if let wait = await limiter.acquire("\(route) \(Self.clientKey(request.remoteAddress))") {
            throw APIError.tooManyRequests(retryAfterSeconds: max(1, Int(wait.rounded(.up))))
        }
        return try await next.respond(to: request)
    }

    static func clientKey(_ address: SocketAddress?) -> String {
        guard case .v6(let v6)? = address else {
            return address?.ipAddress ?? "unknown"
        }
        let bytes = withUnsafeBytes(of: v6.address.sin6_addr) { Array($0) }
        if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
            return bytes[12...].map(String.init).joined(separator: ".")
        }
        return bytes.prefix(8).map { String(format: "%02x", $0) }.joined() + "/64"
    }
}
