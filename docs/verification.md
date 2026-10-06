# Проверка Budget Service поверх PostgreSQL

Все запросы ниже выполнены 2026-10-07 против сервиса, запущенного в docker compose, с настоящей базой `netly_budget`. Ответы не редактировались: это фактический вывод `curl` и `psql`, отформатированный `jq`. Токен — development JWT пользователя `3f2a8c1e-7b4d-4e9a-b5c6-1d2e3f4a5b6c`:

```bash
TOKEN=$(scripts/dev-token.sh 3f2a8c1e-7b4d-4e9a-b5c6-1d2e3f4a5b6c)
curl -X POST http://localhost:8082/api/v1/subscriptions \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name": "Netflix", "price": 119.88, "billingCycle": "yearly", "nextChargeDate": "2026-10-15"}'
```

Схема данных и обоснование индексов: [`database.md`](database.md).

Сервис `profile` в этой проверке не участвует, поэтому `budget` запускается с `--no-deps`.

## 1. Миграции: схема с нуля и откат последней миграции

База пустая (`docker compose down -v`). Команда миграций создаёт всю схему, откат убирает только индекс из миграции 002, а сервер отказывается стартовать на откаченной схеме, пока миграции не применят снова.

```console
$ docker compose run --rm budget-migrate
2026-10-06T20:45:52+0000 info netly-budget: [App] Connected to PostgreSQL 16.15 at postgres:5432, database netly_budget as netly
2026-10-06T20:45:52+0000 info netly-budget: [PostgresMigrations] Migrating 001_create_budget_schema from group _hb_default 
2026-10-06T20:45:52+0000 info netly-budget: [PostgresMigrations] Migrating 002_add_goal_status_index from group _hb_default 
2026-10-06T20:45:52+0000 info netly-budget: [App] Database schema is up to date
```

```console
$ psql -c "\dt"
              List of relations
 Schema |        Name        | Type  | Owner 
--------+--------------------+-------+-------
 public | _hb_pg_migrations  | table | netly
 public | debts              | table | netly
 public | goal_contributions | table | netly
 public | goals              | table | netly
 public | subscriptions      | table | netly
(5 rows)

```

```console
$ psql -c "\d goal_contributions"
                   Table "public.goal_contributions"
   Column   |           Type           | Collation | Nullable | Default 
------------+--------------------------+-----------+----------+---------
 id         | uuid                     |           | not null | 
 goal_id    | uuid                     |           | not null | 
 amount     | numeric(12,2)            |           | not null | 
 note       | text                     |           |          | 
 created_at | timestamp with time zone |           | not null | now()
Indexes:
    "goal_contributions_pkey" PRIMARY KEY, btree (id)
    "goal_contributions_goal_created_idx" btree (goal_id, created_at, id)
Check constraints:
    "goal_contributions_amount_check" CHECK (amount > 0::numeric)
    "goal_contributions_note_check" CHECK (char_length(note) <= 200)
Foreign-key constraints:
    "goal_contributions_goal_id_fkey" FOREIGN KEY (goal_id) REFERENCES goals(id) ON DELETE CASCADE

```

```console
$ docker compose run --rm budget rollback
2026-10-06T20:45:53+0000 info netly-budget: [App] Connected to PostgreSQL 16.15 at postgres:5432, database netly_budget as netly
2026-10-06T20:45:53+0000 info netly-budget: [PostgresMigrations] Reverting 002_add_goal_status_index from group _hb_default 
2026-10-06T20:45:53+0000 info netly-budget: [App] Database schema is at 001_create_budget_schema
```

```console
$ psql -c "SELECT indexname FROM pg_indexes WHERE tablename = 'goals' ORDER BY 1"
       indexname        
------------------------
 goals_pkey
 goals_user_created_idx
(2 rows)

```

```console
$ docker compose run --rm --no-deps budget    # сервер на откаченной схеме
2026-10-06T20:45:53+0000 warning netly-budget: [App] JWT_SECRET is the public development secret; set a private one outside local development
2026-10-06T20:45:53+0000 info netly-budget: [App] Connected to PostgreSQL 16.15 at postgres:5432, database netly_budget as netly
2026-10-06T20:45:53+0000 info netly-budget: [PostgresMigrations] Migrating 002_add_goal_status_index from group _hb_default  (dry run)
2026-10-06T20:45:53+0000 critical netly-budget: [App] Database schema is out of date; run `App migrate` first

exit code: 1
```

```console
$ docker compose run --rm budget-migrate
2026-10-06T20:45:54+0000 info netly-budget: [App] Connected to PostgreSQL 16.15 at postgres:5432, database netly_budget as netly
2026-10-06T20:45:54+0000 info netly-budget: [PostgresMigrations] Migrating 002_add_goal_status_index from group _hb_default 
2026-10-06T20:45:54+0000 info netly-budget: [App] Database schema is up to date
```

## 2. Подключение к базе при старте

Строка подключения собирается из `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` (см. [`.env.example`](../.env.example)); сервис явно логирует, куда подключился.

```console
$ docker compose logs budget
2026-10-06T20:45:54+0000 warning netly-budget: [App] JWT_SECRET is the public development secret; set a private one outside local development
2026-10-06T20:45:54+0000 info netly-budget: [App] Connected to PostgreSQL 16.15 at postgres:5432, database netly_budget as netly
2026-10-06T20:45:54+0000 info netly-budget: [HummingbirdCore] Server started and listening on 0.0.0.0:8082
```

## 3. CRUD поверх базы

### Подписки

Повторное создание `netflix` в другом регистре упирается в уникальный индекс `subscriptions_user_name_key` и возвращает `409`.

```http
POST /api/v1/subscriptions

{
  "name": "Netflix",
  "price": 119.88,
  "billingCycle": "yearly",
  "nextChargeDate": "2026-10-15"
}
```

Ответ: `201`

```json
{
  "billingCycle": "yearly",
  "createdAt": "2026-10-06T20:45:54Z",
  "id": "7b1aad28-5444-4332-854d-a81ec05bcf09",
  "monthlyCost": 9.99,
  "name": "Netflix",
  "nextChargeDate": "2026-10-15",
  "price": 119.88,
  "updatedAt": "2026-10-06T20:45:54Z"
}
```

```http
POST /api/v1/subscriptions

{
  "name": "netflix",
  "price": 9.99,
  "billingCycle": "monthly",
  "nextChargeDate": "2026-10-20"
}
```

Ответ: `409`

```json
{
  "code": "conflict",
  "detail": "A subscription with the same name already exists",
  "instance": "/api/v1/subscriptions",
  "status": 409,
  "title": "Conflict",
  "type": "about:blank"
}
```

```http
POST /api/v1/subscriptions

{
  "name": "Spotify",
  "price": 4.99,
  "billingCycle": "monthly",
  "nextChargeDate": "2026-10-20"
}
```

Ответ: `201`

```json
{
  "billingCycle": "monthly",
  "createdAt": "2026-10-06T20:45:54Z",
  "id": "bf71f56e-284c-4184-b124-965f3c845923",
  "monthlyCost": 4.99,
  "name": "Spotify",
  "nextChargeDate": "2026-10-20",
  "price": 4.99,
  "updatedAt": "2026-10-06T20:45:54Z"
}
```

```http
PATCH /api/v1/subscriptions/bf71f56e-284c-4184-b124-965f3c845923

{
  "price": 5.99
}
```

Ответ: `200`

```json
{
  "billingCycle": "monthly",
  "createdAt": "2026-10-06T20:45:54Z",
  "id": "bf71f56e-284c-4184-b124-965f3c845923",
  "monthlyCost": 5.99,
  "name": "Spotify",
  "nextChargeDate": "2026-10-20",
  "price": 5.99,
  "updatedAt": "2026-10-06T20:45:54Z"
}
```

```http
DELETE /api/v1/subscriptions/7b1aad28-5444-4332-854d-a81ec05bcf09
```

Ответ: `204`


```http
GET /api/v1/subscriptions/7b1aad28-5444-4332-854d-a81ec05bcf09
```

Ответ: `404`

```json
{
  "code": "not_found",
  "detail": "Subscription 7b1aad28-5444-4332-854d-a81ec05bcf09 was not found",
  "instance": "/api/v1/subscriptions/7b1aad28-5444-4332-854d-a81ec05bcf09",
  "status": 404,
  "title": "Not found",
  "type": "about:blank"
}
```

```http
GET /api/v1/subscriptions
```

Ответ: `200`

```json
{
  "items": [
    {
      "billingCycle": "monthly",
      "createdAt": "2026-10-06T20:45:54Z",
      "id": "bf71f56e-284c-4184-b124-965f3c845923",
      "monthlyCost": 5.99,
      "name": "Spotify",
      "nextChargeDate": "2026-10-20",
      "price": 5.99,
      "updatedAt": "2026-10-06T20:45:54Z"
    }
  ],
  "limit": 50,
  "offset": 0,
  "total": 1
}
```

### Задолженности

```http
POST /api/v1/debts

{
  "creditor": "Kaspi Bank",
  "amount": 240000,
  "dueDate": "2027-10-01"
}
```

Ответ: `201`

```json
{
  "amount": 240000,
  "createdAt": "2026-10-06T20:45:54Z",
  "creditor": "Kaspi Bank",
  "dueDate": "2027-10-01",
  "id": "f0ca8bb2-186b-4ca9-be85-c3f9323a6fb1",
  "monthlyPayment": 20000,
  "updatedAt": "2026-10-06T20:45:54Z"
}
```

```http
PATCH /api/v1/debts/f0ca8bb2-186b-4ca9-be85-c3f9323a6fb1

{
  "amount": 180000
}
```

Ответ: `200`

```json
{
  "amount": 180000,
  "createdAt": "2026-10-06T20:45:54Z",
  "creditor": "Kaspi Bank",
  "dueDate": "2027-10-01",
  "id": "f0ca8bb2-186b-4ca9-be85-c3f9323a6fb1",
  "monthlyPayment": 15000,
  "updatedAt": "2026-10-06T20:45:54Z"
}
```

```http
GET /api/v1/debts/f0ca8bb2-186b-4ca9-be85-c3f9323a6fb1
```

Ответ: `200`

```json
{
  "amount": 180000,
  "createdAt": "2026-10-06T20:45:54Z",
  "creditor": "Kaspi Bank",
  "dueDate": "2027-10-01",
  "id": "f0ca8bb2-186b-4ca9-be85-c3f9323a6fb1",
  "monthlyPayment": 15000,
  "updatedAt": "2026-10-06T20:45:54Z"
}
```

### Цели и фильтр по статусу

`GET /goals?status=active` — запрос, под который создан индекс `goals_user_status_idx` (миграция 002). Архивная цель в выборку не попадает.

```http
POST /api/v1/goals

{
  "name": "Laptop",
  "targetAmount": 1500,
  "savedAmount": 300,
  "targetDate": "2027-09-30",
  "priority": 8
}
```

Ответ: `201`

```json
{
  "createdAt": "2026-10-06T20:45:54Z",
  "id": "ab9822c4-57d3-4be9-95a9-4235e2f3d135",
  "name": "Laptop",
  "priority": 8,
  "requiredMonthlyContribution": 100,
  "savedAmount": 300,
  "status": "active",
  "targetAmount": 1500,
  "targetDate": "2027-09-30",
  "updatedAt": "2026-10-06T20:45:54Z"
}
```

```http
POST /api/v1/goals

{
  "name": "Old phone",
  "targetAmount": 400,
  "targetDate": "2027-03-31",
  "priority": 2,
  "status": "archived"
}
```

Ответ: `201`

```json
{
  "createdAt": "2026-10-06T20:45:54Z",
  "id": "41b3494a-f728-4446-8869-94ca429b70ac",
  "name": "Old phone",
  "priority": 2,
  "requiredMonthlyContribution": 0,
  "savedAmount": 0,
  "status": "archived",
  "targetAmount": 400,
  "targetDate": "2027-03-31",
  "updatedAt": "2026-10-06T20:45:54Z"
}
```

```http
GET /api/v1/goals?status=active
```

Ответ: `200`

```json
{
  "items": [
    {
      "createdAt": "2026-10-06T20:45:54Z",
      "id": "ab9822c4-57d3-4be9-95a9-4235e2f3d135",
      "name": "Laptop",
      "priority": 8,
      "requiredMonthlyContribution": 100,
      "savedAmount": 300,
      "status": "active",
      "targetAmount": 1500,
      "targetDate": "2027-09-30",
      "updatedAt": "2026-10-06T20:45:54Z"
    }
  ],
  "limit": 50,
  "offset": 0,
  "total": 1
}
```

## 4. Транзакция: пополнение цели

Пополнение — два шага в одной транзакции: `INSERT INTO goal_contributions` и `UPDATE goals SET saved_amount = saved_amount + amount`. Первое пополнение (200) проходит. Второе (1500) доводит `saved_amount` до 2000 при цели 1500: на втором шаге срабатывает `CHECK goals_saved_within_target`, и PostgreSQL откатывает транзакцию целиком, включая уже выполненный `INSERT`.

Для демонстрации на время двух запросов в PostgreSQL включался `log_statement = 'all'`.

```http
POST /api/v1/goals/ab9822c4-57d3-4be9-95a9-4235e2f3d135/contributions

{
  "amount": 200,
  "note": "September salary"
}
```

Ответ: `201`

```json
{
  "contribution": {
    "amount": 200,
    "createdAt": "2026-10-06T20:45:54Z",
    "goalId": "ab9822c4-57d3-4be9-95a9-4235e2f3d135",
    "id": "829c6983-1811-44ba-8362-f938e7d55caf",
    "note": "September salary"
  },
  "goal": {
    "createdAt": "2026-10-06T20:45:54Z",
    "id": "ab9822c4-57d3-4be9-95a9-4235e2f3d135",
    "name": "Laptop",
    "priority": 8,
    "requiredMonthlyContribution": 83.34,
    "savedAmount": 500,
    "status": "active",
    "targetAmount": 1500,
    "targetDate": "2027-09-30",
    "updatedAt": "2026-10-06T20:45:54Z"
  }
}
```

```http
POST /api/v1/goals/ab9822c4-57d3-4be9-95a9-4235e2f3d135/contributions

{
  "amount": 1500
}
```

Ответ: `422`

```json
{
  "code": "validation_failed",
  "detail": "1 field is invalid",
  "errors": [
    {
      "code": "exceeds_target",
      "field": "amount",
      "message": "savedAmount plus amount must not exceed the goal's targetAmount"
    }
  ],
  "instance": "/api/v1/goals/ab9822c4-57d3-4be9-95a9-4235e2f3d135/contributions",
  "status": 422,
  "title": "Validation failed",
  "type": "about:blank"
}
```

```console
$ docker compose logs postgres    # только запросы к goal_contributions и goals за время двух пополнений
LOG:  execute <unnamed>: BEGIN;
LOG:  execute <unnamed>: INSERT INTO goal_contributions (id, goal_id, amount, note)
DETAIL:  parameters: $1 = '829c6983-1811-44ba-8362-f938e7d55caf', $2 = '200', $3 = 'September salary', $4 = 'ab9822c4-57d3-4be9-95a9-4235e2f3d135', $5 = '3f2a8c1e-7b4d-4e9a-b5c6-1d2e3f4a5b6c'
LOG:  execute <unnamed>: UPDATE goals SET saved_amount = saved_amount + $1, updated_at = now()
DETAIL:  parameters: $1 = '200', $2 = 'ab9822c4-57d3-4be9-95a9-4235e2f3d135'
LOG:  execute <unnamed>: COMMIT;
LOG:  execute <unnamed>: BEGIN;
LOG:  execute <unnamed>: INSERT INTO goal_contributions (id, goal_id, amount, note)
DETAIL:  parameters: $1 = '5bc91d6b-315f-4c1d-a392-e804d82aacef', $2 = '1500', $3 = NULL, $4 = 'ab9822c4-57d3-4be9-95a9-4235e2f3d135', $5 = '3f2a8c1e-7b4d-4e9a-b5c6-1d2e3f4a5b6c'
LOG:  execute <unnamed>: UPDATE goals SET saved_amount = saved_amount + $1, updated_at = now()
DETAIL:  parameters: $1 = '1500', $2 = 'ab9822c4-57d3-4be9-95a9-4235e2f3d135'
ERROR:  new row for relation "goals" violates check constraint "goals_saved_within_target"
DETAIL:  Failing row contains (ab9822c4-57d3-4be9-95a9-4235e2f3d135, 3f2a8c1e-7b4d-4e9a-b5c6-1d2e3f4a5b6c, Laptop, 1500.00, 2000.00, 2027-09-30, 8, active, 2026-10-06 20:45:54.794526+00, 2026-10-06 20:45:54.939931+00).
LOG:  execute <unnamed>: ROLLBACK;
```

```http
GET /api/v1/goals/ab9822c4-57d3-4be9-95a9-4235e2f3d135
```

Ответ: `200`

```json
{
  "createdAt": "2026-10-06T20:45:54Z",
  "id": "ab9822c4-57d3-4be9-95a9-4235e2f3d135",
  "name": "Laptop",
  "priority": 8,
  "requiredMonthlyContribution": 83.34,
  "savedAmount": 500,
  "status": "active",
  "targetAmount": 1500,
  "targetDate": "2027-09-30",
  "updatedAt": "2026-10-06T20:45:54Z"
}
```

```http
GET /api/v1/goals/ab9822c4-57d3-4be9-95a9-4235e2f3d135/contributions
```

Ответ: `200`

```json
{
  "items": [
    {
      "amount": 200,
      "createdAt": "2026-10-06T20:45:54Z",
      "goalId": "ab9822c4-57d3-4be9-95a9-4235e2f3d135",
      "id": "829c6983-1811-44ba-8362-f938e7d55caf",
      "note": "September salary"
    }
  ],
  "limit": 50,
  "offset": 0,
  "total": 1
}
```

```console
$ psql -c "SELECT amount, note FROM goal_contributions WHERE goal_id = 'ab9822c4-57d3-4be9-95a9-4235e2f3d135'"
 amount |       note       
--------+------------------
 200.00 | September salary
(1 row)

```

Итог: `savedAmount` остался 500, а в `goal_contributions` одна запись, а не две. `INSERT` второго пополнения выполнился, но был отменён вместе с транзакцией.

Тот же сценарий закреплён интеграционным тестом `contributionPastTargetRollsBackBothSteps` в [`PostgresIntegrationTests.swift`](../services/budget-service/Tests/AppTests/PostgresIntegrationTests.swift).

## 5. Сохранность данных между перезапусками

Контейнеры удаляются целиком (`docker compose down` без `-v`), том `netly_pgdata` остаётся. После повторного запуска миграции ничего не применяют (схема уже актуальна), а ответы API совпадают с ответами до перезапуска побайтно.

```console
$ docker compose down    # контейнеры удалены, том pgdata остаётся
netly_pgdata
```

```console
$ docker compose up -d postgres && docker compose run --rm budget-migrate && docker compose up -d --no-deps budget
2026-10-06T20:46:03+0000 info netly-budget: [App] Connected to PostgreSQL 16.15 at postgres:5432, database netly_budget as netly
2026-10-06T20:46:03+0000 info netly-budget: [App] Database schema is up to date
```

```http
GET /api/v1/subscriptions
```

Ответ: `200`

```json
{
  "items": [
    {
      "billingCycle": "monthly",
      "createdAt": "2026-10-06T20:45:54Z",
      "id": "bf71f56e-284c-4184-b124-965f3c845923",
      "monthlyCost": 5.99,
      "name": "Spotify",
      "nextChargeDate": "2026-10-20",
      "price": 5.99,
      "updatedAt": "2026-10-06T20:45:54Z"
    }
  ],
  "limit": 50,
  "offset": 0,
  "total": 1
}
```

```http
GET /api/v1/debts
```

Ответ: `200`

```json
{
  "items": [
    {
      "amount": 180000,
      "createdAt": "2026-10-06T20:45:54Z",
      "creditor": "Kaspi Bank",
      "dueDate": "2027-10-01",
      "id": "f0ca8bb2-186b-4ca9-be85-c3f9323a6fb1",
      "monthlyPayment": 15000,
      "updatedAt": "2026-10-06T20:45:54Z"
    }
  ],
  "limit": 50,
  "offset": 0,
  "total": 1
}
```

```http
GET /api/v1/goals
```

Ответ: `200`

```json
{
  "items": [
    {
      "createdAt": "2026-10-06T20:45:54Z",
      "id": "ab9822c4-57d3-4be9-95a9-4235e2f3d135",
      "name": "Laptop",
      "priority": 8,
      "requiredMonthlyContribution": 83.34,
      "savedAmount": 500,
      "status": "active",
      "targetAmount": 1500,
      "targetDate": "2027-09-30",
      "updatedAt": "2026-10-06T20:45:54Z"
    },
    {
      "createdAt": "2026-10-06T20:45:54Z",
      "id": "41b3494a-f728-4446-8869-94ca429b70ac",
      "name": "Old phone",
      "priority": 2,
      "requiredMonthlyContribution": 0,
      "savedAmount": 0,
      "status": "archived",
      "targetAmount": 400,
      "targetDate": "2027-03-31",
      "updatedAt": "2026-10-06T20:45:54Z"
    }
  ],
  "limit": 50,
  "offset": 0,
  "total": 2
}
```

```http
GET /api/v1/goals/ab9822c4-57d3-4be9-95a9-4235e2f3d135/contributions
```

Ответ: `200`

```json
{
  "items": [
    {
      "amount": 200,
      "createdAt": "2026-10-06T20:45:54Z",
      "goalId": "ab9822c4-57d3-4be9-95a9-4235e2f3d135",
      "id": "829c6983-1811-44ba-8362-f938e7d55caf",
      "note": "September salary"
    }
  ],
  "limit": 50,
  "offset": 0,
  "total": 1
}
```

```console
$ diff <ответы до перезапуска> <ответы после перезапуска>
GET /api/v1/subscriptions: identical
GET /api/v1/debts: identical
GET /api/v1/goals: identical
GET /api/v1/goals/ab9822c4-57d3-4be9-95a9-4235e2f3d135/contributions: identical
```
