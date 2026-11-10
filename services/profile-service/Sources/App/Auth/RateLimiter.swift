import Foundation
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
            guard windows[key] != nil || windows.count < maximumTrackedKeys else {
                return window
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
        let client = request.remoteAddress?.ipAddress ?? "unknown"
        if let wait = await limiter.acquire("\(route) \(client)") {
            throw APIError.tooManyRequests(retryAfterSeconds: max(1, Int(wait.rounded(.up))))
        }
        return try await next.respond(to: request)
    }
}
