import Foundation
import Logging

/// In-process cache of `GET /api/v1/summary`, one entry per user, valid for a fixed time to live.
/// Writes that change the summary call `invalidate`, so a client never reads its own stale numbers.
/// Failures are never stored: the next request recomputes.
actor SummaryCache {
    static let defaultTTL: TimeInterval = 60
    static let defaultCapacity = 10_000

    private struct Entry {
        let summary: CommitmentsSummary
        let expiresAt: Date
    }

    private let ttl: TimeInterval
    private let capacity: Int
    private let clock: @Sendable () -> Date
    private let logger: Logger
    private var entries: [UUID: Entry] = [:]
    /// Counts invalidations; a computation that overlapped one must not store its (possibly stale) result.
    /// ponytail: one counter for all users, so a write by anyone only skips caching of overlapping computations; per-user counters if that matters.
    private var invalidations = 0

    /// A `ttl` of zero turns caching off: every request computes.
    init(
        ttl: TimeInterval = SummaryCache.defaultTTL,
        capacity: Int = SummaryCache.defaultCapacity,
        clock: @escaping @Sendable () -> Date = { Date() },
        logger: Logger = makeLogger()
    ) {
        self.ttl = ttl
        self.capacity = capacity
        self.clock = clock
        self.logger = logger
    }

    /// The user's cached summary, or the result of `compute` when there is none or it expired.
    func summary(
        for userID: UUID,
        compute: @Sendable () async throws -> CommitmentsSummary
    ) async throws -> (summary: CommitmentsSummary, isHit: Bool) {
        let metadata: Logger.Metadata = ["userId": "\(userID.uuidString.lowercased())"]
        let now = clock()
        if let entry = entries[userID] {
            if now < entry.expiresAt {
                logger.info("summary cache hit", metadata: metadata)
                return (entry.summary, true)
            }
            entries[userID] = nil
            logger.info("summary cache expired", metadata: metadata)
        }
        logger.info("summary cache miss", metadata: metadata)

        let invalidationsBefore = invalidations
        let summary: CommitmentsSummary
        do {
            summary = try await compute()
        } catch {
            logger.error("summary computation failed", metadata: metadata.merging(["error": "\(String(reflecting: error))"]) { $1 })
            throw error
        }

        if ttl > 0, invalidationsBefore == invalidations {
            store(summary, for: userID, now: now)
            logger.info("summary cache store", metadata: metadata.merging(["ttlSeconds": "\(Int(ttl))"]) { $1 })
        }
        return (summary, false)
    }

    /// Drops the user's entry; `reason` names the write that made it outdated, e.g. `goals updated`.
    func invalidate(userID: UUID, reason: String) {
        invalidations += 1
        entries[userID] = nil
        logger.info("summary cache invalidated", metadata: ["userId": "\(userID.uuidString.lowercased())", "reason": "\(reason)"])
    }

    private func store(_ summary: CommitmentsSummary, for userID: UUID, now: Date) {
        if entries.count >= capacity, entries[userID] == nil {
            entries = entries.filter { $0.value.expiresAt > now }
            // ponytail: linear scan, only when full of live entries; a sorted structure if capacity grows large.
            if entries.count >= capacity, let oldest = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt }) {
                entries[oldest.key] = nil
            }
        }
        entries[userID] = Entry(summary: summary, expiresAt: now.addingTimeInterval(ttl))
    }
}
