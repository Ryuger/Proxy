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

## Почему раньше падало и что исправлено
- `docker` показывал help из-за неверной передачи аргументов в PowerShell-функцию — исправлено (`Invoke-DockerChecked -Args @(...)`).
- Пакеты `c-icap-modules`/`squidclamav` отсутствуют в части базовых образов Debian, из-за чего ломался build.
- Теперь ICAP поднимается через локальный Python ICAP service (`solution/proxy/cicap/icap_server.py`) и больше не зависит от нестабильных пакетных имен в apt.
- Инициализация SSL DB для Squid выполняется с авто-поиском `security_file_certgen`/`cert_tool`.
- Если запуск compose падает — скрипт завершится с ошибкой, а не сообщит ложный успех.

## Порты
- `3128` — proxy (Squid)
- `1344` — ICAP
- `8080` — quarantine portal

## Production-заметки
- Замените demo CA на корпоративный PKI Root CA.
- Выдайте Root CA на Android устройства через MDM как trusted cert.
- Примените Brave managed policy (см. `../client/MOBILE_CLIENT_SETUP.md`).
- Минимальный ICAP сервис можно расширить: добавить фактическую проверку через `clamd` и блокировку зараженных объектов по хэшу/статусу.
