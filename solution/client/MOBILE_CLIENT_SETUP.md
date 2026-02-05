# Настройка клиентской стороны (Android + Brave) для бесплатного self-hosted решения

Документ для связки:
- Squid + ssl_bump
- c-icap + ClamAV
- Внутренний портал карантина

## 1) Что обязательно на Android (через MDM)

1. Используйте Android Enterprise (`Work Profile` или `Fully Managed`).
2. Разверните сертификат `proxy-root-ca.crt` с прокси-сервера в доверенные сертификаты рабочего профиля.
3. Включите:
   - `Always-on VPN`
   - `Block connections without VPN`
4. Направляйте весь трафик через корпоративный VPN/прокси.
5. Заблокируйте прямой DNS/DoH вне корпоративного контура.

> Без доверенного Root CA HTTPS-инспекция работать не будет.

## 2) Политики Brave (Managed App Configuration)

Минимальные параметры:
- `DownloadRestrictions = 3`
- Запрет неуправляемых расширений
- Отключение пользовательских профилей
- Отключение QUIC/UDP443 на уровне сети

Пример JSON (шаблон для MDM):

```json
{
  "DownloadRestrictions": 3,
  "BrowserGuestModeEnabled": false,
  "BrowserAddPersonEnabled": false,
  "ExtensionInstallBlocklist": ["*"],
  "QuicAllowed": false,
  "ProxyMode": "fixed_servers",
  "ProxyServerMode": "http=PROXY_IP:3128;https=PROXY_IP:3128"
}
```

## 3) Как сделать, чтобы устройство не считало прокси угрозой

1. Корневой сертификат должен быть выпущен вашей корпоративной PKI.
2. У сертификата должны быть валидные сроки и корректные поля `Key Usage / Basic Constraints`.
3. Сертификат ставится MDM-ом как доверенный корпоративный, а не вручную пользователем.
4. Для доменов с pinning (банк, госуслуги и т.п.) включите исключения из MITM в Squid.

## 4) Проверка после раскатки

1. На клиенте открыть HTTPS-сайт и проверить цепочку сертификата: issuer = ваш Root CA.
2. Попробовать скачать PDF/ZIP/EXE:
   - в Brave загрузка блокируется,
   - файл появляется в портале `http://<proxy-or-portal>:8080`.
3. Проверить, что при отключении VPN интернет не работает (требование Block without VPN).

## 5) Лицензии (всё бесплатно)

- Squid — GPLv2
- c-icap — LGPL
- ClamAV — GPLv2
- Flask/Python — BSD/PSF

Это позволяет держать полностью бесплатное решение в собственной инфраструктуре,
но ответственность за поддержку/обновления/мониторинг лежит на вашей команде.
