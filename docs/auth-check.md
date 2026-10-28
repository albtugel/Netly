# Протокол проверки сценариев доступа

Проверка выполнена 2026-10-28 против Profile Service (`:8081`) и Budget Service (`:8082`), запущенных поверх PostgreSQL из ветки с единым форматом ошибок. Ответы не редактировались; убраны только заголовки `Date`, `Server`, `Content-Length` и `Connection`.

## Участники

| Участник       | Как получен токен                                                    | Роль в токене |
| -------------- | -------------------------------------------------------------------- | ------------- |
| Гость          | Без заголовка `Authorization`                                        | —             |
| `user-check`   | `POST /api/v1/auth/register`, затем `POST /api/v1/auth/login`        | `user`        |
| `other-check`  | То же; второй обычный пользователь                                   | `user`        |
| `admin-check`  | Регистрация, `App make-admin admin-check@netly.kz`, затем вход       | `admin`       |

Полезная нагрузка токенов `user-check` и `admin-check`:

```json
{"exp":1793212880,"sub":"bad23e74-f254-4f98-8e27-a43192e4c922","iat":1793211980,"role":"user"}
{"exp":1793212880,"role":"admin","sub":"c409cadc-9c2a-4b9b-a5e7-9dafc58943bc","iat":1793211980}
```

```bash
U=<токен user-check>; O=<токен other-check>; A=<токен admin-check>
```

## Сценарий 1. Операция только для администратора: `GET /api/v1/admin/users`

### 1.1. Без токена — 401

```
$ curl -i http://localhost:8081/api/v1/admin/users
HTTP/1.1 401 Unauthorized
Content-Type: application/json; charset=utf-8

{"error":{"code":"unauthorized","details":[],"message":"Missing bearer token"}}
```

### 1.2. Роль `user` — 403

```
$ curl -i http://localhost:8081/api/v1/admin/users -H "Authorization: Bearer $U"
HTTP/1.1 403 Forbidden
Content-Type: application/json; charset=utf-8

{"error":{"code":"forbidden","details":[],"message":"Requires the admin role"}}
```

### 1.3. Роль `admin` — 200

```
$ curl -i "http://localhost:8081/api/v1/admin/users?limit=3" -H "Authorization: Bearer $A"
HTTP/1.1 200 OK
content-type: application/json; charset=utf-8

{"items":[{"createdAt":"2026-10-28T18:24:30Z","email":"admin@netly.kz","id":"7bc6c8fc-841d-4c5e-8c9e-38bcf604fb65","role":"admin"},{"createdAt":"2026-10-28T18:24:30Z","email":"user@netly.kz","id":"521a053b-c61a-4808-9a28-46cdd45edb15","role":"user"},{"createdAt":"2026-10-28T18:26:18Z","email":"user-check@netly.kz","id":"bad23e74-f254-4f98-8e27-a43192e4c922","role":"user"}],"limit":3,"offset":0,"total":5}
```

Аутентификация и роль проверяются раздельно: `AccessTokenAuthenticator` отвечает `401`, если токена нет или он недействителен, а `RoleGuard(.admin)` — `403`, если токен действителен, но роль не та.

## Сценарий 2. Удаление записи: `DELETE /api/v1/goals/{id}`

Цель `c70c1c3f-75fb-499d-8d80-8354e41c88f9` создана пользователем `user-check`:

```
$ curl -X POST http://localhost:8082/api/v1/goals -H "Authorization: Bearer $U" -H "Content-Type: application/json" \
    -d '{"name": "Laptop", "targetAmount": 1500, "targetDate": "2027-12-31", "priority": 8}'
```

### 2.1. Без токена — 401

```
$ curl -i -X DELETE http://localhost:8082/api/v1/goals/c70c1c3f-75fb-499d-8d80-8354e41c88f9
HTTP/1.1 401 Unauthorized
Content-Type: application/json; charset=utf-8

{"error":{"code":"unauthorized","details":[],"message":"Missing bearer token"}}
```

### 2.2. Другой пользователь (`other-check`) — 404

```
$ curl -i -X DELETE http://localhost:8082/api/v1/goals/c70c1c3f-75fb-499d-8d80-8354e41c88f9 -H "Authorization: Bearer $O"
HTTP/1.1 404 Not Found
Content-Type: application/json; charset=utf-8

{"error":{"code":"not_found","details":[],"message":"Goal c70c1c3f-75fb-499d-8d80-8354e41c88f9 was not found"}}
```

### 2.3. Администратор (`admin-check`) — 404

```
$ curl -i -X DELETE http://localhost:8082/api/v1/goals/c70c1c3f-75fb-499d-8d80-8354e41c88f9 -H "Authorization: Bearer $A"
HTTP/1.1 404 Not Found
Content-Type: application/json; charset=utf-8

{"error":{"code":"not_found","details":[],"message":"Goal c70c1c3f-75fb-499d-8d80-8354e41c88f9 was not found"}}
```

### 2.4. Владелец (`user-check`) — 204, после чего цели нет

```
$ curl -i -X DELETE http://localhost:8082/api/v1/goals/c70c1c3f-75fb-499d-8d80-8354e41c88f9 -H "Authorization: Bearer $U"
HTTP/1.1 204 No Content

$ curl -i http://localhost:8082/api/v1/goals/c70c1c3f-75fb-499d-8d80-8354e41c88f9 -H "Authorization: Bearer $U"
HTTP/1.1 404 Not Found
Content-Type: application/json; charset=utf-8

{"error":{"code":"not_found","details":[],"message":"Goal c70c1c3f-75fb-499d-8d80-8354e41c88f9 was not found"}}
```

Удалять, изменять и читать запись может только ее владелец: каждый SQL-запрос содержит условие `WHERE id = $1 AND user_id = $2`, где `user_id` взят из токена. Чужая запись отвечает `404`, а не `403`, чтобы не подтверждать ее существование. Администратор чужие финансы не видит: управление пользователями — его функция, бюджеты — нет.

## Итог

| Операция                          | Гость | `user`              | `admin` | Владелец записи |
| --------------------------------- | ----- | ------------------- | ------- | --------------- |
| `GET /api/v1/admin/users`         | 401   | 403                 | 200     | —               |
| `DELETE /api/v1/goals/{id}`       | 401   | 404 (чужая запись)  | 404     | 204             |

Права различаются на деле: одна и та же операция дает разные коды для разных участников, и каждый отказ приходит в едином формате `{"error": {"code", "message", "details"}}`.

## Единый формат для остальных ошибок

```
$ curl -i -X POST http://localhost:8081/api/v1/auth/login -H "Content-Type: application/json" -d '{'
HTTP/1.1 400 Bad Request
Content-Type: application/json; charset=utf-8

{"error":{"code":"malformed_json","details":[],"message":"Request body is not valid JSON"}}

$ curl -i http://localhost:8081/api/v1/nope
HTTP/1.1 404 Not Found
Content-Type: application/json; charset=utf-8

{"error":{"code":"not_found","details":[],"message":"Not Found"}}

$ curl -i -X POST http://localhost:8082/api/v1/goals -H "Authorization: Bearer $U" -H "Content-Type: application/json" \
    -d '{"name": " ", "targetAmount": -5, "targetDate": "2020-01-01", "priority": 11}'
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/json; charset=utf-8

{"error":{"code":"validation_failed","details":[{"code":"blank","field":"name","message":"Must not be blank"},{"code":"must_be_positive","field":"targetAmount","message":"Must be greater than 0"},{"code":"must_be_in_future","field":"targetDate","message":"Must be after 2026-10-28"},{"code":"out_of_range","field":"priority","message":"Must be between 1 and 10"}],"message":"4 fields are invalid"}}
```

Ошибка `500` в работающем сервисе не воспроизводится запросом; ее формат проверяет тест `unexpectedErrorHidesDetails` (Budget Service): необработанное исключение дает `{"error": {"code": "internal_error", "message": "An unexpected error occurred", "details": []}}` без описания исключения и стектрейса.
