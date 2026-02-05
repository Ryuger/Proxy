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

## Что исправлено относительно прошлой версии
- Генерация CA больше не вызывает `sh` внутри `alpine/openssl`.
- ICAP-сервис больше не тянется из несуществующего `moul/icap`, теперь используется локальный Docker build `solution/proxy/cicap/Dockerfile`.
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
