import Foundation
import Vapor

actor RateLimiter {
    let limit: Int
    let window: TimeInterval
    private let now: @Sendable () -> Date
    private var windows: [String: (start: Date, count: Int)] = [:]
    private let maximumTrackedKeys = 10_000

    init(limit: Int, window: TimeInterval, now: @escaping @Sendable () -> Date = { Date() }) {
        self.limit = limit
        self.window = window
        self.now = now
    }

    func acquire(_ key: String) -> TimeInterval? {
        let current = now()
        if windows.count >= maximumTrackedKeys {
            windows = windows.filter { current.timeIntervalSince($0.value.start) < window }
        }
        guard let entry = windows[key], current.timeIntervalSince(entry.start) < window else {
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
        let client = request.remoteAddress?.ipAddress ?? "unknown"
        if let wait = await limiter.acquire("\(request.url.path) \(client)") {
            throw APIError.tooManyRequests(retryAfterSeconds: max(1, Int(wait.rounded(.up))))
        }
        return try await next.respond(to: request)
    }
}
