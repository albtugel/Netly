# Summary cache: manual verification

A protocol of the manual check of the Budget Service summary cache: the normal path (miss, hits, expiry) and the failure path (invalidation after writes, PostgreSQL stopped). Sections 1 to 5 are the real output of one run on 2026-11-18 against the docker compose stack (build 861fe4b); section 6 repeats the database-down check on the final build (742cb40) and adds a paused database; in sections 1 to 5 only the `Date`, `Server` and `Content-Length` headers are left out and JSON is compacted with `jq -c`; section 6 notes what its transcript cut.

## What is checked

`GET /api/v1/summary` adds up the user's monthly commitments from three reads (subscriptions, debts, active goals). The result is cached per user in the service's memory for `SUMMARY_CACHE_TTL_SECONDS` and dropped by every write that changes it. The `X-Cache` response header (`HIT` or `MISS`) and the service log show which path a request took.

| Expectation | Where it is shown |
| ----------- | ----------------- |
| A repeat request within the TTL is faster and does not read the database | [1](#1-normal-path-miss-then-hits), and [4](#4-failure-path-postgresql-is-stopped): the hit is served while the database is down |
| After the TTL the entry expires and is recomputed | [2](#2-normal-path-the-entry-expires) |
| Update, delete and a goal contribution invalidate the entry; no stale numbers | [3](#3-failure-path-invalidation-after-writes) |
| A failed computation is not cached, the answer is a controlled error, the service keeps serving | [4](#4-failure-path-postgresql-is-stopped) |
| The 5 second limit also holds when the connection is open but the server is silent (paused database), on the final build | [6](#6-re-check-on-the-final-build-742cb40-stop-and-pause) |
| Hits, misses, invalidations and failures are logged | log fragments in every step |

## Setup

The TTL is shortened to 20 seconds so that expiry can be seen; the default is 60.

```bash
docker compose up -d --wait postgres
docker compose run --rm budget-migrate
SUMMARY_CACHE_TTL_SECONDS=20 docker compose up -d --no-deps --build budget
```

`profile` is not needed, so `budget` starts with `--no-deps`. A token for a fresh user (`bf238cfa-bc8f-45d9-8c13-9565c0f3f063`) comes from the development script:

```bash
TOKEN=$(scripts/dev-token.sh bf238cfa-bc8f-45d9-8c13-9565c0f3f063)
BASE=http://localhost:8082
```

Every call below is `curl -s -X <method> $BASE<path> -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json'` (plus `-d` for a body), timed with `-w '%{time_total}'`.

Three records to summarize (each create also drops the user's entry, see the first three log lines):

```text
POST /api/v1/subscriptions  {"name":"Netflix","price":119.88,"billingCycle":"yearly","nextChargeDate":"2026-12-15"}   201, monthlyCost 9.99
POST /api/v1/debts          {"creditor":"Kaspi Bank","amount":1200,"dueDate":"2027-02-28"}                              201, monthlyPayment 300
POST /api/v1/goals          {"name":"Laptop","targetAmount":1500,"savedAmount":300,"targetDate":"2027-11-18","priority":8}   201, requiredMonthlyContribution 100
```

## 1. Normal path: miss, then hits

```text
$ curl -s -X GET /api/v1/summary
HTTP 200  X-Cache: MISS  time: 4.3 ms
{"computedAt":"2026-11-18T09:26:49Z","counts":{"debts":1,"goals":1,"subscriptions":1},"debtsMonthly":300,"goalsRequiredMonthly":100,"subscriptionsMonthly":9.99,"totalMonthlyCommitments":409.99}

$ curl -s -X GET /api/v1/summary
HTTP 200  X-Cache: HIT  time: 1.5 ms
{"computedAt":"2026-11-18T09:26:49Z", … the same body, `computedAt` unchanged}

$ curl -s -X GET /api/v1/summary
HTTP 200  X-Cache: HIT  time: 1.6 ms
```

The first request is computed (4.3 ms); the next two are about three times faster (1.5 and 1.6 ms) and carry the old `computedAt`, which shows that nothing was recomputed. Here PostgreSQL runs on the same machine and holds three rows, so the gap is small; it grows with the database's distance and the user's data.

Log:

```text
2026-11-18T09:26:49+0000 info netly-budget: reason=subscriptions created userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache invalidated
2026-11-18T09:26:49+0000 info netly-budget: reason=debts created userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache invalidated
2026-11-18T09:26:49+0000 info netly-budget: reason=goals created userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache invalidated
2026-11-18T09:26:49+0000 info netly-budget: userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache miss
2026-11-18T09:26:49+0000 info netly-budget: ttlSeconds=20 userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache store
2026-11-18T09:26:50+0000 info netly-budget: userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache hit
2026-11-18T09:26:50+0000 info netly-budget: userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache hit
```

The three `invalidated` lines are the setup writes; then one `miss` with its `store`, and two `hit` lines with no database work in between.

## 2. Normal path: the entry expires

After waiting 21 seconds (TTL 20):

```text
$ curl -s -X GET /api/v1/summary
HTTP 200  X-Cache: MISS  time: 11.0 ms
{"computedAt":"2026-11-18T09:27:11Z", … same figures}

$ curl -s -X GET /api/v1/summary
HTTP 200  X-Cache: HIT  time: 2.7 ms
```

`computedAt` moved from `09:26:49` to `09:27:11`: the entry was recomputed.

```text
2026-11-18T09:27:11+0000 info netly-budget: userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache expired
2026-11-18T09:27:11+0000 info netly-budget: userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache miss
2026-11-18T09:27:11+0000 info netly-budget: ttlSeconds=20 userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache store
2026-11-18T09:27:11+0000 info netly-budget: userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache hit
```

## 3. Failure path: invalidation after writes

Each write must make the next read a `MISS` with the new numbers, never the cached ones. Before every write the entry was cached (the previous request was a `HIT` or a fresh `MISS`).

| Write | Write time | Next `GET /summary` | Figures |
| ----- | ---------- | ------------------- | ------- |
| `PATCH /subscriptions/{id}` `{"price":239.76}` | 200, 3.8 ms | `MISS`, 3.5 ms | `subscriptionsMonthly` 9.99 to 19.98, `totalMonthlyCommitments` 409.99 to 419.98 |
| repeat read | | `HIT`, 1.7 ms | the same |
| `DELETE /debts/{id}` | 204, 2.4 ms | `MISS`, 3.3 ms | `debtsMonthly` 300 to 0, `counts.debts` 0, total 119.98 |
| `POST /goals/{id}/contributions` `{"amount":600}` | 201, 4.1 ms | `MISS`, 3.0 ms | `goalsRequiredMonthly` 100 to 50, total 69.98 |

```text
2026-11-18T09:27:11+0000 info netly-budget: reason=subscriptions updated userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache invalidated
2026-11-18T09:27:11+0000 info netly-budget: userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache miss
2026-11-18T09:27:11+0000 info netly-budget: ttlSeconds=20 userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache store
2026-11-18T09:27:11+0000 info netly-budget: userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache hit
2026-11-18T09:27:11+0000 info netly-budget: reason=debts deleted userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache invalidated
2026-11-18T09:27:11+0000 info netly-budget: userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache miss
2026-11-18T09:27:11+0000 info netly-budget: ttlSeconds=20 userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache store
2026-11-18T09:27:11+0000 info netly-budget: reason=goal contribution added userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache invalidated
2026-11-18T09:27:11+0000 info netly-budget: userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache miss
2026-11-18T09:27:11+0000 info netly-budget: ttlSeconds=20 userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache store
2026-11-18T09:27:11+0000 info netly-budget: userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache hit
```

Each `invalidated` line names the write (`reason`), and the `miss` after it is the next read.

## 4. Failure path: PostgreSQL is stopped

```bash
docker stop netly-postgres-1
```

**Within the TTL the cached entry is still served**, without touching the database (the last line of the previous log fragment), and `/health` does not depend on the database either:

```text
$ curl -s -X GET /api/v1/summary
HTTP 200  X-Cache: HIT  time: 1.3 ms
{"computedAt":"2026-11-18T09:27:11Z","counts":{"debts":0,"goals":1,"subscriptions":1},"debtsMonthly":0,"goalsRequiredMonthly":50,"subscriptionsMonthly":19.98,"totalMonthlyCommitments":69.98}

$ curl -s -X GET /health
HTTP 200  time: 1.5 ms
{"service":"netly-budget","status":"ok"}
```

**After the TTL a miss needs the database.** The connection pool does not fail while the host `postgres` is unresolvable, it keeps retrying, so the computation has a 5 second limit. The client gets the usual error body, not a hang, and nothing is cached:

```text
$ curl -s -X GET /api/v1/summary
HTTP 503  time: 5016.0 ms
{"error":{"code":"service_unavailable","details":[],"message":"The summary could not be computed in time; try again later"}}

$ curl -s -X GET /api/v1/summary
HTTP 503  time: 5010.3 ms
{"error":{"code":"service_unavailable","details":[],"message":"The summary could not be computed in time; try again later"}}

$ curl -s -X GET /health
HTTP 200  time: 2.7 ms
```

The second request was a `miss` again, so the failure was not remembered. The service kept answering `/health` throughout and did not crash. Log (the pool's retry lines repeat every 0.1 to 1.5 seconds, 12 before the first timeout and 3 before the second; one is shown):

```text
2026-11-18T09:27:32+0000 info netly-budget: userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache expired
2026-11-18T09:27:32+0000 info netly-budget: userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache miss
2026-11-18T09:27:32+0000 info netly-budget: psql_connection_id=1 psql_error=PSQLError(code: connectionError, underlying: DNS error: SocketAddressError.UnknownHost: Name or service not known (error -2) for host postgres, port 5432) [PostgresNIO] Connection creation failed
 … 11 more identical "Connection creation failed" lines …
2026-11-18T09:27:37+0000 error netly-budget: error=App.APIError(status: 503 Service Unavailable, code: "service_unavailable", message: "The summary could not be computed in time; try again later", fieldErrors: []) userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary computation failed
2026-11-18T09:27:37+0000 info netly-budget: userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache miss
 … 3 "Connection creation failed" lines …
2026-11-18T09:27:42+0000 error netly-budget: error=App.APIError(status: 503 Service Unavailable, code: "service_unavailable", message: "The summary could not be computed in time; try again later", fieldErrors: []) userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary computation failed
```

The `error` lines are the `summary computation failed` entries of the cache; the long `error=` text is the thrown `APIError`.

## 5. Recovery

```bash
docker start netly-postgres-1
```

```text
$ curl -s -X GET /api/v1/summary
HTTP 200  X-Cache: MISS  time: 849.4 ms
{"computedAt":"2026-11-18T09:27:42Z", … figures as before}

$ curl -s -X GET /api/v1/summary
HTTP 200  X-Cache: HIT  time: 1.5 ms
```

The first request after the restart waits for the pool to reconnect (849 ms), later ones are served from the cache again.

```text
2026-11-18T09:27:42+0000 info netly-budget: userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache miss
2026-11-18T09:27:43+0000 info netly-budget: ttlSeconds=20 userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache store
2026-11-18T09:27:43+0000 info netly-budget: userId=bf238cfa-bc8f-45d9-8c13-9565c0f3f063 [App] summary cache hit
```

## 6. Re-check on the final build (742cb40): stop and pause

Sections 1 to 5 were taken on build 861fe4b, where the 5 second limit was a structured task group. A review found that this limit is not a hard bound: PostgresNIO does not stop a query that is already written to an open connection, and the task group waits for its children. Commit 742cb40 runs the computation in its own task and answers from whichever finishes first, the result or the timer. This section repeats the stop check on that build and adds the pause check, which the first run did not have. It was taken on 2026-11-18 between 09:49:22 and 09:50:42 UTC, TTL 20 seconds, a fresh user (`147e8f91-12d3-41f4-851f-c42537f6fbf0`).

```bash
docker compose build budget          # image from commit 742cb40
docker compose up -d --wait postgres
SUMMARY_CACHE_TTL_SECONDS=20 docker compose up -d --no-deps --force-recreate budget
docker stop netly-postgres-1         # case A, then docker start netly-postgres-1
docker pause netly-postgres-1        # case B, then docker unpause netly-postgres-1
```

Every call is the same `curl` as in the setup. The transcript below is the script's output: the time in front of a call is when it finished, and the script cut each response body at 170 characters (`cut -c1-170`), so long JSON ends mid-field. Before each case the TTL was allowed to pass, so the request after the stop or pause is a cache miss.

```text
user 147e8f91-12d3-41f4-851f-c42537f6fbf0, TTL 20 s, started 2026-11-18T09:49:22Z
09:49:22 POST /api/v1/subscriptions  HTTP 201  X-Cache: -  4.8 ms  {"billingCycle":"yearly","createdAt":"2026-11-18T09:49:22Z","id":"28cb3af8-b55b-4903-b00a-5b5f76716414","monthlyCost":9.99,"name":"Netflix","nextChargeDate":"2026-12-15",
09:49:22 GET /api/v1/summary  HTTP 200  X-Cache: MISS  4.4 ms  {"computedAt":"2026-11-18T09:49:22Z","counts":{"debts":0,"goals":0,"subscriptions":1},"debtsMonthly":0,"goalsRequiredMonthly":0,"subscriptionsMonthly":9.99,"totalMonthlyC
09:49:22 GET /api/v1/summary  HTTP 200  X-Cache: HIT  1.5 ms  {"computedAt":"2026-11-18T09:49:22Z","counts":{"debts":0,"goals":0,"subscriptions":1},"debtsMonthly":0,"goalsRequiredMonthly":0,"subscriptionsMonthly":9.99,"totalMonthlyC
```

### A. `docker stop`: the host name stops resolving

```text
09:49:48 GET /api/v1/summary  HTTP 503  X-Cache: -  5010.6 ms  {"error":{"code":"service_unavailable","details":[],"message":"The summary could not be computed in time; try again later"}}
09:49:48 GET /health  HTTP 200  X-Cache: -  1.7 ms  {"service":"netly-budget","status":"ok"}
09:49:49 GET /api/v1/summary  HTTP 200  X-Cache: MISS  366.0 ms  {"computedAt":"2026-11-18T09:49:49Z","counts":{"debts":0,"goals":0,"subscriptions":1},"debtsMonthly":0,"goalsRequiredMonthly":0,"subscriptionsMonthly":9.99,"totalMonthlyC
09:49:49 GET /api/v1/summary  HTTP 200  X-Cache: HIT  1.7 ms  {"computedAt":"2026-11-18T09:49:49Z","counts":{"debts":0,"goals":0,"subscriptions":1},"debtsMonthly":0,"goalsRequiredMonthly":0,"subscriptionsMonthly":9.99,"totalMonthlyC
```

The first request is a miss with no database: 503 after 5010.6 ms, in the standard error body, and `/health` still answers. After `docker start` the first request is a miss that reconnects (366.0 ms), then hits again. The log (the pool's `Connection creation failed` line, an unresolvable host `postgres`, appears 12 times during the 5 seconds; the first and the last are shown and the 10 between them are skipped):

```text
2026-11-18T09:49:43+0000 info netly-budget: userId=147e8f91-12d3-41f4-851f-c42537f6fbf0 [App] summary cache expired
2026-11-18T09:49:43+0000 info netly-budget: userId=147e8f91-12d3-41f4-851f-c42537f6fbf0 [App] summary cache miss
2026-11-18T09:49:43+0000 info netly-budget: psql_connection_id=1 psql_error=PSQLError(code: connectionError, underlying: DNS error: SocketAddressError.UnknownHost: Name or service not known (error -2) for host postgres, port 5432) [PostgresNIO] Connection creation failed
 … 10 more identical "Connection creation failed" lines (09:49:43 to 09:49:48) …
2026-11-18T09:49:48+0000 info netly-budget: psql_connection_id=1 psql_error=PSQLError(code: connectionError, underlying: DNS error: SocketAddressError.UnknownHost: Name or service not known (error -2) for host postgres, port 5432) [PostgresNIO] Connection creation failed
2026-11-18T09:49:48+0000 error netly-budget: error=App.APIError(status: 503 Service Unavailable, code: "service_unavailable", message: "The summary could not be computed in time; try again later", fieldErrors: []) userId=147e8f91-12d3-41f4-851f-c42537f6fbf0 [App] summary computation failed
2026-11-18T09:49:49+0000 info netly-budget: userId=147e8f91-12d3-41f4-851f-c42537f6fbf0 [App] summary cache miss
2026-11-18T09:49:49+0000 info netly-budget: ttlSeconds=20 userId=147e8f91-12d3-41f4-851f-c42537f6fbf0 [App] summary cache store
2026-11-18T09:49:49+0000 info netly-budget: userId=147e8f91-12d3-41f4-851f-c42537f6fbf0 [App] summary cache hit
```

The `error` line is the cache's `summary computation failed` entry; its long text is the thrown `APIError`.

### B. `docker pause`: the connection stays open and the server answers nothing

Before the pause, a miss on the healthy database (`200 MISS, 5.8 ms`) left an open connection in the pool, and the TTL was allowed to pass again. The pause is not the same failure as a stop: the connection stays open and the query is never answered, and no connection error is logged.

```text
09:50:10 GET /api/v1/summary  HTTP 200  X-Cache: MISS  5.8 ms  {"computedAt":"2026-11-18T09:50:10Z","counts":{"debts":0,"goals":0,"subscriptions":1},"debtsMonthly":0,"goalsRequiredMonthly":0,"subscriptionsMonthly":9.99,"totalMonthlyC
09:50:31 docker pause netly-postgres-1
09:50:36 GET /api/v1/summary  HTTP 503  X-Cache: -  5004.3 ms  {"error":{"code":"service_unavailable","details":[],"message":"The summary could not be computed in time; try again later"}}
09:50:41 GET /api/v1/summary  HTTP 503  X-Cache: -  5007.6 ms  {"error":{"code":"service_unavailable","details":[],"message":"The summary could not be computed in time; try again later"}}
09:50:41 GET /health  HTTP 200  X-Cache: -  2.1 ms  {"service":"netly-budget","status":"ok"}
09:50:42 docker unpause netly-postgres-1
09:50:42 GET /api/v1/summary  HTTP 200  X-Cache: MISS  4.3 ms  {"computedAt":"2026-11-18T09:50:42Z","counts":{"debts":0,"goals":0,"subscriptions":1},"debtsMonthly":0,"goalsRequiredMonthly":0,"subscriptionsMonthly":9.99,"totalMonthlyC
09:50:42 GET /api/v1/summary  HTTP 200  X-Cache: HIT  3.1 ms  {"computedAt":"2026-11-18T09:50:42Z","counts":{"debts":0,"goals":0,"subscriptions":1},"debtsMonthly":0,"goalsRequiredMonthly":0,"subscriptionsMonthly":9.99,"totalMonthlyC
```

Both requests ended in 503 after 5004.3 and 5007.6 ms. The second one was a miss again, so the failure was not cached; `/health` answered at once; after `docker unpause` the first request was a miss (4.3 ms) and the next a hit. The log has no `Connection creation failed` lines in this case:

```text
2026-11-18T09:50:10+0000 info netly-budget: userId=147e8f91-12d3-41f4-851f-c42537f6fbf0 [App] summary cache expired
2026-11-18T09:50:10+0000 info netly-budget: userId=147e8f91-12d3-41f4-851f-c42537f6fbf0 [App] summary cache miss
2026-11-18T09:50:10+0000 info netly-budget: ttlSeconds=20 userId=147e8f91-12d3-41f4-851f-c42537f6fbf0 [App] summary cache store
2026-11-18T09:50:31+0000 info netly-budget: userId=147e8f91-12d3-41f4-851f-c42537f6fbf0 [App] summary cache expired
2026-11-18T09:50:31+0000 info netly-budget: userId=147e8f91-12d3-41f4-851f-c42537f6fbf0 [App] summary cache miss
2026-11-18T09:50:36+0000 error netly-budget: error=App.APIError(status: 503 Service Unavailable, code: "service_unavailable", message: "The summary could not be computed in time; try again later", fieldErrors: []) userId=147e8f91-12d3-41f4-851f-c42537f6fbf0 [App] summary computation failed
2026-11-18T09:50:36+0000 info netly-budget: userId=147e8f91-12d3-41f4-851f-c42537f6fbf0 [App] summary cache miss
2026-11-18T09:50:41+0000 error netly-budget: error=App.APIError(status: 503 Service Unavailable, code: "service_unavailable", message: "The summary could not be computed in time; try again later", fieldErrors: []) userId=147e8f91-12d3-41f4-851f-c42537f6fbf0 [App] summary computation failed
2026-11-18T09:50:42+0000 info netly-budget: userId=147e8f91-12d3-41f4-851f-c42537f6fbf0 [App] summary cache miss
2026-11-18T09:50:42+0000 info netly-budget: ttlSeconds=20 userId=147e8f91-12d3-41f4-851f-c42537f6fbf0 [App] summary cache store
2026-11-18T09:50:42+0000 info netly-budget: userId=147e8f91-12d3-41f4-851f-c42537f6fbf0 [App] summary cache hit
```

### Notes and limits

- **An invalid first attempt.** The first try of this section was thrown away: the Docker VM disk was full after the image builds, PostgreSQL could not restart after `docker stop` (`No space left on device`), and the recovery and pause steps ran against a dead database. Its stop case also gave 503 at 5.0 s (5018.4 ms), but none of its numbers are used here. After pruning dangling images the whole scenario was run again; the numbers above are from that second run.
- **The old build was not run on the pause case.** This section shows that the final build answers 503 after about 5 seconds when the connection is open but silent. It does not show that build 861fe4b hung there. The unit test `computationThatIgnoresCancellationStillAnswersServiceUnavailableInTime` covers the reason with a wait that cancellation cannot interrupt.
- **Abandoned reads are not stopped.** On timeout the service answers and cancels the computation, but a query already written is still waiting for the database, and its connection stays busy in the pool until the database answers or the connection breaks. Repeated stalled misses could use up the pool; this was not measured.
- **Only the 5 seconds are bounded.** The limit applies to a cache miss. A cached entry is served at once in every case above.

## Result

| Criterion | Result |
| --------- | ------ |
| Repeat request within the TTL is faster and does not read the database | 4.3 ms `MISS` against 1.5 and 1.6 ms `HIT`; `computedAt` unchanged; a hit is still served with the database stopped; the unit test counts repository reads (3 for a miss, 0 for a hit) |
| Expiry | `expired` then `miss`, `computedAt` advanced after 21 s |
| Explicit invalidation | PATCH, DELETE and a contribution each turned the next read into a `MISS` with new figures |
| Logs | `miss`, `store`, `hit`, `expired`, `invalidated` (with `reason`), `summary computation failed`, all with `userId` |
| Controlled error path (build 861fe4b, database stopped) | 503 `service_unavailable` in the standard error body after 5.0 s, no hang, no crash, `/health` unaffected, failures not cached, recovery on the first request after the database returned |
| Controlled error path (final build 742cb40, section 6) | Database stopped: 503 after 5010.6 ms, `/health` 200, first request after `docker start` a `MISS` (366.0 ms). Database paused on an open connection: 503 after 5004.3 and 5007.6 ms, nothing cached, `/health` 200, after `docker unpause` a `MISS` (4.3 ms) then a `HIT` |

A first run of this scenario, before the 5 second limit existed, showed why it is needed: with the database stopped, the two cache misses did not answer at all and `curl` gave up after its own 30 second limit (`HTTP 000`). The limit and its test (`hangingComputationAnswersServiceUnavailableAndIsNotCached`) were added after that run; a later review showed the first version of the limit was not a hard bound, which led to section 6.
