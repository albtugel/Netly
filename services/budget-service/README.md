# netly-budget

Responsibility: subscriptions, debts, savings goals, free-balance calculation.

Framework: Hummingbird 2. Default port: 8082.

## Run

```bash
swift run
```

| Variable | Default   | Purpose            |
| -------- | --------- | ------------------ |
| `PORT`   | `8082`    | HTTP port          |
| `JWT_SECRET` | development secret | HS256 key shared with Profile Service, at least 32 bytes |

## Test

```bash
swift test
# or, without a local Swift 6.2 toolchain:
docker run --rm -v "$PWD":/src -w /src swift:6.2-noble swift test
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
| 422    | `validation_failed` | A field is missing, has the wrong type or breaks a rule     |
| 500    | `internal_error`    | Unexpected failure; details are logged, not returned        |

## Endpoints

All `/api/v1` routes require `Authorization: Bearer <jwt>` and only see the caller's own records; another user's record answers `404`.

| Method | Path                       | Description                                       |
| ------ | -------------------------- | ------------------------------------------------- |
| GET    | `/health`                  | Service health check                              |
| POST   | `/api/v1/{resource}`       | Create; `201` with a `Location` header            |
| GET    | `/api/v1/{resource}`       | List, `?limit=1..100` (default 50) `&offset=0..`  |
| GET    | `/api/v1/{resource}/{id}`  | Read one                                          |
| PATCH  | `/api/v1/{resource}/{id}`  | Partial update; the merged record is re-validated |
| DELETE | `/api/v1/{resource}/{id}`  | Delete; `204`                                     |

`{resource}` is `subscriptions`, `debts` or `goals`.

| Resource     | Fields                                                                                                                                                              | Read-only                     |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| subscription | `name` 1–100 chars; `price` > 0, ≤ 1 000 000; `billingCycle` `weekly` \| `monthly` \| `quarterly` \| `yearly`; `nextChargeDate`                                     | `monthlyCost`                 |
| debt         | `creditor` 1–100 chars; `amount` > 0, ≤ 100 000 000; `dueDate` after today                                                                                         | `monthlyPayment`              |
| goal         | `name` 1–100 chars; `targetAmount` > 0; `savedAmount` 0..`targetAmount` (default 0); `targetDate` after today; `priority` 1–10; `status` `active` \| `completed` \| `archived` | `requiredMonthlyContribution` |

Every resource also has read-only `id`, `createdAt` and `updatedAt`. Money has at most two decimal places; dates are `YYYY-MM-DD`. A "date after today" rule applies only when the client sets or changes that date, so an overdue debt can still be edited.

Storage is in memory for now; PostgreSQL arrives in a later step.

`GET /health` response:

```json
{ "status": "ok", "service": "netly-budget" }
```
