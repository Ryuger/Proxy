# Windows-only запуск прокси (без Linux-сервера)

Если у вас нет Linux-сервера — это нормально. Стек запускается на Windows Server/Windows 11 через Docker Desktop или Docker Engine.

## Требования
- Windows 10/11 Pro или Windows Server 2019+
- Docker Desktop (или Docker Engine + Compose plugin)
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

## Что делает скрипт
- Создаёт `runtime` структуру (конфиги, логи, certs).
- Генерирует demo Root CA (если нет файла сертификата).
- Поднимает контейнеры `squid`, `c-icap`, `clamd`, `portal`.

## Порты
- `3128` — proxy (Squid)
- `1344` — ICAP
- `8080` — quarantine portal

## Production-заметки
- Замените demo CA на корпоративный PKI Root CA.
- Выдайте Root CA на Android устройства через MDM как trusted cert.
- Примените Brave managed policy (см. `../client/MOBILE_CLIENT_SETUP.md`).
