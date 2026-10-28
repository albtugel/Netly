# netly-profile

Зона ответственности: регистрация, вход и выдача токена, роли; далее — онбординг, источники дохода, обязательные расходы.

Фреймворк: Vapor + Fluent + JWT. Порт по умолчанию: 8081. База: `netly_profile`.

## Запуск

Настройки читаются из тех же переменных, что у Budget Service: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_SSLMODE`, `JWT_SECRET` (не короче 32 байт), `PORT`.

```bash
docker compose up -d postgres
set -a && . ../../.env && set +a
export DB_NAME=netly_profile PORT=8081
swift run App migrate --yes          # создать таблицу users
swift run App                        # сервер на :8081
swift run App make-admin a@netly.kz  # выдать роль admin существующему аккаунту
```

## Эндпоинты

| Метод | Путь                    | Доступ       | Описание                                          |
| ----- | ----------------------- | ------------ | ------------------------------------------------- |
| GET   | `/health`               | все          | Проверка работоспособности                         |
| POST  | `/api/v1/auth/register` | все          | Регистрация, `201` и аккаунт с ролью `user`        |
| POST  | `/api/v1/auth/login`    | все          | Вход, `200` и JWT на 15 минут                      |
| GET   | `/api/v1/users/me`      | user, admin  | Аккаунт владельца токена                           |
| GET   | `/api/v1/admin/users`   | admin        | Все аккаунты постранично; `user` получает `403`    |

Контракт: [`docs/api/profile-service.openapi.yaml`](../../docs/api/profile-service.openapi.yaml). Ошибки — `{"error": {"code": …, "message": …, "details": […]}}`, как у Budget Service.

## Пароли и токены

- Пароль 8 символов – 72 байта (bcrypt не учитывает байты после 72-го). Хранится только bcrypt-хеш с cost 12; хеширование выполняется в пуле потоков, чтобы не блокировать event loop.
- Неверный пароль и неизвестный email дают одинаковый `401 Invalid email or password`; для неизвестного email всё равно проверяется хеш, чтобы время ответа не выдавало, зарегистрирован ли адрес.
- Токен — JWT HS256 с `sub` (id пользователя), `role`, `iat`, `exp` = `iat` + 900 с. Budget Service проверяет его подпись общим `JWT_SECRET`.
- Поле `role` в теле регистрации игнорируется. Роль `admin` выдаёт только команда `App make-admin`.

## Тесты

```bash
docker run --rm -v "$PWD":/src -w /src swift:6.2-noble swift test
```

Проверки доступа и валидации работают без базы. Регистрация, вход и роли проверяются на PostgreSQL, если заданы `DB_*`:

```bash
docker compose up -d postgres
docker run --rm --network netly_default -v "$PWD":/src -w /src \
  -e DB_HOST=postgres -e DB_NAME=netly_profile -e DB_USER=netly -e DB_PASSWORD=netly \
  swift:6.2-noble swift test
```
