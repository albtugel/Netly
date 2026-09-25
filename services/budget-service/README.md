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

## Test

```bash
swift test
# or, without a local Swift 6.2 toolchain:
docker run --rm -v "$PWD":/src -w /src swift:6.2-noble swift test
```

## Endpoints

| Method | Path      | Description         |
| ------ | --------- | ------------------- |
| GET    | `/health` | Service health check |

Example response:

```json
{ "status": "ok", "service": "netly-budget" }
```
