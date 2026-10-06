# netly-budget

Responsibility: subscriptions, debts, savings goals and their contributions, free-balance calculation.

Framework: Hummingbird 2. Default port: 8082.

## Run

```bash
cp ../../.env.example ../../.env    # once; adjust if needed
set -a && . ../../.env && set +a
swift run
```

| Variable | Default   | Purpose            |
| -------- | --------- | ------------------ |
| `PORT`   | `8082`    | HTTP port          |
| `JWT_SECRET` | development secret | HS256 key shared with Profile Service, at least 32 bytes |
| `DB_HOST` | — | PostgreSQL host, required |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_NAME` | — | Database name, required |
| `DB_USER` | — | Database user, required |
| `DB_PASSWORD` | — | Database password, required |
| `DB_SSLMODE` | — | `require` forces TLS; otherwise the connection is plain, as on the internal compose network |

The connection is configured only through these variables; [`.env.example`](../../.env.example) lists them with local defaults. The service refuses to start if a required one is missing, and on start-up logs the server it connected to:

```
info netly-budget: [App] Connected to PostgreSQL 16.x at postgres:5432, database netly_budget as netly
```

## Database schema and migrations

The schema lives in migrations under [`Sources/App/Database/Migrations`](Sources/App/Database/Migrations), applied with [`postgres-migrations`](https://github.com/hummingbird-project/postgres-migrations):

| Command        | What it does                                                         |
| -------------- | -------------------------------------------------------------------- |
| `App migrate`  | Applies pending migrations in one transaction; on an empty database it creates the whole schema |
| `App rollback` | Reverts the newest migration                                         |
| `App` / `App serve` | Starts the server; refuses to start if the schema is behind the code |

Under docker compose the one-shot `budget-migrate` container runs `migrate` before `budget` starts; run the commands by hand with `docker compose run --rm budget-migrate` and `docker compose run --rm budget rollback`.

Tables, keys, constraints, index rationale and the ER diagram: [`docs/database.md`](../../docs/database.md).

## Test

```bash
swift test
# or, without a local Swift 6.2 toolchain:
docker run --rm -v "$PWD":/src -w /src swift:6.2-noble swift test
```

Integration tests against a real PostgreSQL run only when the `DB_*` variables are set:

```bash
set -a && . ../../.env && set +a && swift test
```

## Errors

Every error is returned as `application/problem+json` (RFC 9457) with two extensions: a stable machine-readable `code` and, for validation failures, an `errors` array with one entry per invalid field. Validation collects all violations of a request instead of stopping at the first one.

```json
{
  "type": "about:blank",
  "title": "Validation failed",
  "status": 422,
  "code": "validation_failed",
  "detail": "2 fields are invalid",
  "instance": "/api/v1/goals",
  "errors": [
    { "field": "name", "code": "blank", "message": "Must not be blank" },
    { "field": "priority", "code": "out_of_range", "message": "Must be between 1 and 10" }
  ]
}
```

| Status | `code`              | When                                                        |
| ------ | ------------------- | ----------------------------------------------------------- |
| 400    | `malformed_json`    | The body is not valid JSON                                  |
| 401    | `unauthorized`      | Missing, malformed, foreign-signed or expired bearer token  |
| 404    | `not_found`         | Unknown route, or a record that does not exist for the user |
| 409    | `conflict`          | A subscription with the same name (case-insensitive) exists |
| 422    | `validation_failed` | A field is missing, has the wrong type or breaks a rule     |
| 500    | `internal_error`    | Unexpected failure; details are logged, not returned        |

## Endpoints

Full contract: [`docs/api/budget-service.openapi.yaml`](../../docs/api/budget-service.openapi.yaml). Rules and examples for every operation: [`docs/api/budget-service.md`](../../docs/api/budget-service.md). For a development token, run `scripts/dev-token.sh` from the repository root.

All `/api/v1` routes require `Authorization: Bearer <jwt>` and only see the caller's own records; another user's record answers `404`.

| Method | Path                       | Description                                       |
| ------ | -------------------------- | ------------------------------------------------- |
| GET    | `/health`                  | Service health check                              |
| POST   | `/api/v1/{resource}`       | Create; `201` with a `Location` header            |
| GET    | `/api/v1/{resource}`       | List, `?limit=1..100` (default 50) `&offset=0..`  |
| GET    | `/api/v1/{resource}/{id}`  | Read one                                          |
| PATCH  | `/api/v1/{resource}/{id}`  | Partial update; the merged record is re-validated |
| DELETE | `/api/v1/{resource}/{id}`  | Delete; `204`                                     |
| POST   | `/api/v1/goals/{id}/contributions` | Top up a goal: records the contribution and raises `savedAmount` in one transaction; `201` |
| GET    | `/api/v1/goals/{id}/contributions` | The goal's contributions, oldest first, paged like any list |

`{resource}` is `subscriptions`, `debts` or `goals`. `GET /api/v1/goals` also accepts `?status=active|completed|archived`.

| Resource     | Fields                                                                                                                                                              | Read-only                     |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| subscription | `name` 1–100 chars; `price` > 0, ≤ 1 000 000; `billingCycle` `weekly` \| `monthly` \| `quarterly` \| `yearly`; `nextChargeDate`                                     | `monthlyCost`                 |
| debt         | `creditor` 1–100 chars; `amount` > 0, ≤ 100 000 000; `dueDate` after today                                                                                         | `monthlyPayment`              |
| goal         | `name` 1–100 chars; `targetAmount` > 0; `savedAmount` 0..`targetAmount` (default 0); `targetDate` after today; `priority` 1–10; `status` `active` \| `completed` \| `archived` | `requiredMonthlyContribution` |
| contribution | `amount` > 0, `savedAmount + amount` ≤ `targetAmount`; `note` optional, 1–200 chars | `goalId`, no `updatedAt` |

Every resource also has read-only `id`, `createdAt` and `updatedAt`. Money has at most two decimal places; dates are `YYYY-MM-DD`. A "date after today" rule applies only when the client sets or changes that date, so an overdue debt can still be edited.

`GET /health` response:

```json
{ "status": "ok", "service": "netly-budget" }
```
