# Чек-лист проверки безопасности API

Проверены Profile Service (`:8081`) и Budget Service (`:8082`) по пунктам OWASP API Security Top 10 (2023). Каждый пункт подтвержден кодом и автоматическим тестом; тесты запускаются командой `scripts/test.sh`.

Статусы: **выполнено** (защита уже была), **исправлено** (проблема найдена и устранена в этой работе), **не применимо**, **риск принят** (проблема известна, исправление отложено с обоснованием).

## Обязательные пункты

| № | Проверка | Статус | Как проверено |
| - | -------- | ------ | ------------- |
| 1 | Параметризованные запросы вместо склейки строк (API8, инъекции) | выполнено | Profile Service обращается к базе только через Fluent. Budget Service строит SQL через `PostgresQuery`: в текст запроса попадают только имена таблиц и колонок из статического описания и плейсхолдеры `$1…$n`, значения передаются отдельно. Значение фильтра `?status=` сначала сверяется со списком допустимых. Тест `sqlInjectionPayloadIsStoredAsPlainText`: строка `x'); DROP TABLE subscriptions; --` сохраняется как обычное имя подписки, таблица цела; `?status=active' OR '1'='1` дает 422 `invalid_value`. |
| 2 | Нет лишних полей в ответах (API3) | выполнено | Аккаунт отдается структурой `User.Response` (`id`, `email`, `role`, `createdAt`), хеш пароля в нее не входит. Записи бюджета отдаются структурами `*.Response` без `user_id`. Непредвиденная ошибка возвращает `500 internal_error` с текстом `An unexpected error occurred`, подробности пишутся только в журнал. Тесты `publicAccountShapeHasNoPasswordHash`, `registrationStoresOnlyABcryptHash`, `unexpectedErrorHidesDetails`. |
| 3 | Ограничение частоты запросов на входе и регистрации (API4) | **исправлено** | См. раздел «Найденная проблема». Тесты `eleventhAuthAttemptInAMinuteIsTooManyRequests`, `RateLimiterTests`. |
| 4 | Коды 401/403 на всех защищенных маршрутах (API2, API5) | выполнено | Права проверяет middleware на группе маршрутов, а не каждый обработчик. Без токена, с чужой подписью и с истекшим токеном ответ 401, роль `user` на `/admin/users` получает 403. Тест `everyBudgetRouteRequiresAToken` перебирает все 17 маршрутов Budget Service без токена и ждет 401; тесты `missingTokenIsUnauthorized`, `tokenSignedWithAnotherSecretIsUnauthorized`, `expiredTokenIsUnauthorized`, `userRoleIsForbiddenFromAdminRoutes` в Profile Service. |

## Дополнительные пункты

| № | Проверка | Статус | Как проверено |
| - | -------- | ------ | ------------- |
| 5 | Доступ к чужим объектам (API1, BOLA) | выполнено | Каждый запрос к записи бюджета содержит `WHERE id = $1 AND user_id = $2`, `user_id` берется из токена. Чужая запись отвечает 404. Тесты `showHidesOtherUsersRecords`, `anotherUsersGoalIsNotFound`, `listPaginatesOwnRecordsOnly`. |
| 6 | Массовое присваивание роли (API3) | выполнено | Регистрация читает из тела только `email` и `password`. Тест `roleInRegistrationBodyIsIgnored`. |
| 7 | Хранение паролей | выполнено | bcrypt, cost 12; пароль длиннее 72 байт отклоняется, так как bcrypt не учитывает остаток. Тесты `registrationStoresOnlyABcryptHash`, `passwordLongerThanBcryptLimitIsRejected`. |
| 8 | Перебор email по ответу входа | выполнено | Неверный пароль и неизвестный email дают одинаковый ответ 401 и одинаковое время (хеш проверяется в обоих случаях). Тест `wrongPasswordAndUnknownEmailFailTheSameWay`. |
| 9 | Перебор email через регистрацию | риск принят | Регистрация занятого адреса отвечает 409, по нему можно узнать, что адрес зарегистрирован. Без этого ответа пользователь не поймет, почему не может создать аккаунт; после исправления п. 3 проверять адреса массово не получится (10 запросов в минуту). |
| 10 | Секрет JWT по умолчанию | риск принят | Без `JWT_SECRET` сервисы берут публичный секрет разработки и пишут предупреждение в журнал. Это нужно для запуска `docker compose up` без настройки; в рабочем окружении секрет обязателен и задается через `.env`. |
| 11 | Подробности ошибок и стектрейсы | выполнено | Оба сервиса отдают ошибки в одном формате `{"error": {...}}`, текст исключения в ответ не попадает. Тест `unexpectedErrorHidesDetails`. |
| 12 | CORS | не применимо | Клиент является iOS-приложением, браузерных запросов с других сайтов нет; заголовки CORS не выдаются, и браузер такие запросы не пропустит. |
| 13 | Неограниченная пагинация (API4) | выполнено | `limit` от 1 до 100, огромный `offset` не роняет сервис. Тесты `listValidatesPaging`, `adminListsUsersAfterPromotion`. |

## Найденная проблема: нет ограничения частоты запросов на `/auth/*`

**До.** `POST /api/v1/auth/login` и `POST /api/v1/auth/register` принимали любое число запросов. Это позволяло подбирать пароль без ограничений, а каждый запрос входа стоит около 0,2 с процессорного времени на bcrypt, так что поток запросов нагружал сервер.

Проверка 2026-11-10: сервис запущен в контейнере поверх PostgreSQL, зарегистрирован `ratecheck@netly.kz`, затем 12 попыток входа подряд с неверным паролем:

```bash
for i in $(seq 1 12); do
  curl -s -w '%{http_code} ' -X POST http://localhost:18081/api/v1/auth/login \
    -H "Content-Type: application/json" -d '{"email": "ratecheck@netly.kz", "password": "wrong password"}'
  echo
done
```

Ответы на коде `main` (до исправления): все 12 попыток обработаны, bcrypt вызывался 12 раз.

```
 1: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
 2: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
 3: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
 4: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
 5: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
 6: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
 7: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
 8: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
 9: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
10: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
11: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
12: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
```

**Исправление.** В Profile Service добавлен `RateLimitMiddleware` (`Sources/App/Auth/RateLimiter.swift`) на группе `/auth`: не больше 10 запросов в минуту с одного IP-адреса отдельно для входа и для регистрации. Лишний запрос получает `429 too_many_requests` в общем формате ошибок и заголовок `Retry-After` со временем ожидания в секундах. Middleware стоит до обработчика, поэтому отклоненный запрос не доходит до bcrypt и базы.

**После.**

Те же запросы после исправления: первые 10 попыток обработаны, 11-я и 12-я отклонены без проверки пароля.

```
 1: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
 2: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
 3: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
 4: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
 5: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
 6: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
 7: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
 8: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
 9: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
10: 401 {"error":{"code":"unauthorized","details":[],"message":"Invalid email or password"}}
11: 429 Retry-After: 57 {"error":{"code":"too_many_requests","details":[],"message":"Too many attempts, retry in 57 s"}}
12: 429 Retry-After: 57 {"error":{"code":"too_many_requests","details":[],"message":"Too many attempts, retry in 57 s"}}
```

**Ограничения.** Счетчики хранятся в памяти одного экземпляра сервиса: при нескольких экземплярах лимит считается в каждом отдельно, и для них нужно общее хранилище (Redis). За обратным прокси все запросы придут с адреса прокси; тогда ключом нужно сделать адрес из `X-Forwarded-For`, которому доверяет прокси.
