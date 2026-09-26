# Netly

## Domain

Personal finance: tracking income, mandatory expenses, subscriptions, debts, actual spending and savings goals. The app converts income of different periodicity into a monthly equivalent, computes the free balance and distributes it across goals by priority.

On top of the budget plan, Netly shows the user's route for the day on a map together with the amount spent at each place.

The client is an iOS app built with SwiftUI. The backend consists of three independent microservices written in Swift.

The business problem, user stories with acceptance criteria and the decomposition into microservices: [`docs/requirements.md`](docs/requirements.md).

## Architecture

![Netly architecture](docs/architecture.png)

> The diagram currently shows Profile Service and Budget Service. `spending-service` is described below and will be added to the diagram along with its implementation.

The client talks to all three services directly over HTTPS. Authentication is based on JWT: the token is issued by Profile Service, while Budget Service and Spending Service verify its signature with a shared secret. The token is signed with HS256, carries the user id in `sub` and an expiry in `exp`; the shared `JWT_SECRET` must be at least 32 bytes long, and Budget Service refuses to start otherwise. The databases live on the internal network and are not reachable from outside.

The system contains a single synchronous call, in one direction only: Budget Service asks Profile Service for the monthly income and mandatory expenses. There are no reverse calls and no cycles.

Spending Service neither calls other services nor is called by them, and location data never leaves its own database.

| Service            | Responsibility                                                          | Port |
| ------------------ | ----------------------------------------------------------------------- | ---- |
| `profile-service`  | Authentication, onboarding, income sources, mandatory expenses          | 8081 |
| `budget-service`   | Subscriptions, debts, goals, free-balance calculation                   | 8082 |
| `spending-service` | Actual spending, route, matching purchases to places, daily map         | 8083 |

## Daily Spending Map (planned)

### What the user sees

- The route line for the day.
- Pins at the places where money was spent; the pin size is proportional to the amount.
- Tapping a pin shows the merchant, the time and the amount.
- A daily total broken down by category.

### Where the spending data comes from

- **Apple Pay.** A Shortcuts automation (the `Transaction` trigger, `Wallet` on newer iOS versions) invokes the `Add Expense` App Intent and passes the amount and the merchant name; the app records the time. Third-party apps have no direct access to Apple Pay history: FinanceKit is available only in the United States and the United Kingdom.
- **Manual entry.** For QR payments, transfers, cash and plastic-card payments.

### Matching a purchase to a place

The server looks for the visit during which the purchase was made. If there is no such visit, it takes the nearest route point in time within a 15-minute window. The match is not stored but computed when the day is requested, so it also works when a visit reaches the server later than the purchase.

## Telematics Component

| Link                | Implementation                                                                                                    |
| ------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Moving object       | The user's smartphone                                                                                             |
| Positioning         | GNSS receiver (GPS, GLONASS) via CoreLocation                                                                      |
| Events              | Visits, significant location changes, NFC payment events through the Wallet automation                             |
| Communication link  | Cellular network or Wi-Fi over HTTPS; while offline, data is buffered in SwiftData and sent as a batch             |
| Processing          | Spending Service matches purchases to the route                                                                    |
| Output              | The daily spending map                                                                                             |

Continuous GPS tracking is not used: the route is reconstructed from visits and significant location changes in order to save battery.

## Technology Stack

| Component        | Technology                                   | Language | Storage    |
| ---------------- | -------------------------------------------- | -------- | ---------- |
| Client           | SwiftUI, iOS 17+, MapKit, CoreLocation, App Intents | Swift | SwiftData  |
| Profile Service  | Vapor, Fluent, JWT                           | Swift    | PostgreSQL |
| Budget Service   | Hummingbird, PostgresNIO                     | Swift    | PostgreSQL |
| Spending Service | Hummingbird, PostgresNIO                     | Swift    | PostgreSQL |
| Runtime          | Docker, Docker Compose                       | —        | —          |

The framework choice for each service is justified in [`docs/requirements.md`](docs/requirements.md). In short: Profile Service works with a connected relational model and is responsible for authentication, so it uses the full-featured Vapor with its ORM and JWT module. Budget Service has a flat data model and a mostly computational workload, so it uses the minimalistic Hummingbird with the PostgresNIO driver directly. This is the same contrast as Django versus Flask in the Python ecosystem.

Spending Service uses the same stack as Budget Service: its data model is flat (two tables), coordinates are stored as ordinary columns, and matching by time is done with ordinary SQL — PostGIS and a heavyweight ORM are not needed here.

## Getting Started

Current state: Profile Service and Budget Service both have an implemented skeleton with a `/health` endpoint, so the whole `docker compose` stack builds and starts. Spending Service is designed; its implementation is planned.

Requires Swift 6.2 or newer (Budget Service depends on Hummingbird 2, which needs Swift tools 6.2), or Docker.

### All services via Docker

```bash
docker compose up --build
```

Set `JWT_SECRET` (at least 32 bytes) to override the development secret used by default.

This brings up the `profile`, `budget` and `postgres` containers, with `postgres` hosting two databases (`netly_profile` and `netly_budget`).

Once Spending Service is implemented, a `spending` container and a `netly_spending` database in the same PostgreSQL instance will be added.

### A single service

```bash
cd services/profile-service   # or services/budget-service
swift run
```

### Tests

```bash
cd services/budget-service
swift test
```

Without a local Swift 6.2 toolchain, run the tests in the same image the Dockerfile uses:

```bash
docker run --rm -v "$PWD":/src -w /src swift:6.2-noble swift test
```

### Health check

```bash
curl http://localhost:8081/health
curl http://localhost:8082/health
```

Response:

```json
{ "status": "ok", "service": "netly-profile" }
```

## Repository Layout

```
netly/
├── docs/
│   ├── requirements.md          business problem, user stories, decomposition
│   ├── architecture.drawio      diagram source
│   └── architecture.png
├── scripts/
│   └── init-databases.sh        creates the additional databases in PostgreSQL
├── services/
│   ├── profile-service/
│   ├── budget-service/
│   └── spending-service/        (planned)
├── docker-compose.yml
└── README.md
```
