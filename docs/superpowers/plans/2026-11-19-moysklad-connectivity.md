# План реализации: подключение МойСклад и диагностический Журнал склада

> Статус: утверждён пользователем (2026-11-19); Tasks 1–4 реализованы, Task 5 — регрессия и сборка.
> Спецификация: `docs/superpowers/specs/2026-11-19-moysklad-connectivity-design.md`

## Цель

Реализовать первый безопасный этап API-интеграции: асинхронная проверка готового Access Token, трёхцветный индикатор и локальный диагностический Журнал склада. Бизнес-данные и документы не читать/изменять.

## Ограничения

- Репозиторий `Olega20/Lerua_Zakup`, ветка `main`.
- Исходники менять только через GitHub API; локально — fetch/reset, тесты, analyze и APK build.
- Не менять старый репозиторий.
- Каждый логический этап — отдельный коммит, после него fetch-проверка.
- Не переходить к бизнес-разделам до проверки этого этапа на телефоне и подтверждения пользователя.
- Секреты никогда не включать в тестовые fixture, логи, commit или диагностику.

## Предлагаемые задачи

### Task 1 — доменная модель и API transport
- Добавить типизированные состояния: offline, checking, connected, unauthorized, forbidden, rateLimited, unavailable, missingToken.
- Ввести интерфейс HTTP transport для unit tests и production-реализацию на `dart:io HttpClient`.
- Добавить GET context/employee; Bearer, Accept и gzip headers; 10s timeout.
- Запретить передачу Authorization при redirect на иной host.
- Тесты на статусы, JSON, headers, тайм-аут, socket failure, отсутствие токена, безопасность.
- Коммит: `feat: add MoySklad API connectivity client`.

### Task 2 — API Manager и orchestration
- Связать secure token store, connectivity stream, API client и журнал через один API Manager.
- Проверять при запуске, после сохранения токена, при восстановлении интернета, при foreground resume после >5 минут.
- Периодический опрос раз в 5 минут только в foreground — утверждено пользователем.
- Гарантировать один активный запрос, защиту от stale response после offline/token change и уважение Retry-After при 429.
- Тесты триггеров, single-flight, timeout, cancellation/stale result, reconnect, resume, rate-limit.
- Коммит: `feat: coordinate MoySklad connection checks`.

### Task 3 — трёхцветный индикатор и запуск приложения
- Расширить connectivity state stream до реального API connection state.
- Сохранить красный/жёлтый/зелёный индикатор 4 px.
- Главный экран строится сразу, независимо от secure storage и сети; загрузка токена и проверка происходят асинхронно.
- Удаление токена немедленно исключает connected state и переводит индикатор в yellow, если интернет есть.
- Тесты всех цветов, быстрый первый кадр, ошибки и отсутствие токена.
- Коммит: `feat: show live MoySklad connection status`.

### Task 4 — локальный диагностический Журнал склада
- Выбрать SQLite пакет только после проверки совместимости с текущим Flutter toolchain.
- Создать мигрируемую локальную таблицу событий и repository.
- Хранить безопасные события; исключить токены, auth headers, сырые ответы и данные сотрудника.
- Сохранять не более 500 последних записей — утверждено пользователем.
- Реализовать экран из Settings, список/детали, копирование безопасной диагностики, подтверждение очистки.
- Тесты persistence, ordering, retention, sanitization, empty/error states, copy and clear.
- Коммит: `feat: add local warehouse diagnostics journal`.

### Task 5 — интеграция, регрессия и выпуск
- Подключить сохранение/удаление токена к API Manager.
- Записывать события интернет-соединения, запуска/результата проверки и сохранения/удаления токена в локальный журнал.
- После ручного сохранения токена показывать один краткий Snackbar при неуспешной проверке; автоматические повторы не показывают Snackbar.
- Проверить Snackbar: краткая ошибка только после явного сохранения токена; не спамить на периодических проверках.
- Полный flutter analyze, dart format check, flutter test.
- Сборка debug APK; ручная проверка на Android.
- После подтверждения — release APK и GitHub Release отдельным действием.
- Коммит: `test: verify MoySklad connectivity integration`.

## Definition of Done

- App startup никогда не ждёт сеть/API.
- Нет токена — нет запроса, приложение работает офлайн.
- Только корректный HTTP 200 + JSON даёт green.
- Потеря интернета мгновенно даёт red; восстановление — yellow до успешной проверки.
- Ни один API request не изменяет данные.
- В каждый момент не более одного активного check.
- Тайм-аут 10 секунд; late response не меняет актуальное состояние.
- Токен не раскрывается в любом UI/log/diagnostic path.
- Диагностические записи переживают перезапуск и безопасны для копирования.
- Все тесты/analyze/format/build проходят; ручная проверка выполнена на телефоне.
