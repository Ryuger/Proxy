# Windows-only запуск прокси (без Linux-сервера)

Если у вас нет Linux-сервера — это нормально. Стек запускается на Windows Server/Windows 11 через Docker Desktop.

## Требования
- Windows 10/11 Pro или Windows Server 2019+
- Docker Desktop (включенный Docker Compose v2)
- PowerShell 5.1+ (или PowerShell 7+)

## Быстрый запуск
1. Откройте PowerShell от имени администратора.
2. Перейдите в папку:
   ```powershell
   cd solution\proxy
   ```
3. Запустите одной командой:
   ```powershell
   .\StartProxyServer.ps1
   ```

Или двойным кликом по `StartProxyServer.bat`.

## Почему у вас было "Up", а потом `curl` не работает
- Раньше скрипт не валидировал, что **все** сервисы реально остались running после старта.
- Если `portal` или `squid` падали через секунду, вы видели только частичный список контейнеров.
- Также путь volume для `quarantine_server.py` был неверным относительно `runtime/docker-compose.yml`.

Теперь исправлено:
- корректный путь монтирования: `../../storage/quarantine_server.py`;
- строгая проверка всех сервисов (`squid`, `c-icap`, `clamd`, `portal`), при падении выводятся логи и скрипт завершается с ошибкой.

## Важно по `docker compose ps`
Если вы запускаете команду из `solution\proxy`, нужно так:
```powershell
docker compose -f runtime/docker-compose.yml ps
```

Или перейти в `solution\proxy\runtime` и выполнить обычный `docker compose ps`.

## Порты
- `3128` — proxy (Squid)
- `1344` — ICAP
- `8080` — quarantine portal

## Production-заметки
- Замените demo CA на корпоративный PKI Root CA.
- Выдайте Root CA на Android устройства через MDM как trusted cert.
- Примените Brave managed policy (см. `../client/MOBILE_CLIENT_SETUP.md`).
- Минимальный ICAP сервис можно расширить: добавить фактическую проверку через `clamd` и блокировку зараженных объектов по хэшу/статусу.
