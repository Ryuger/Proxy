#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$ROOT_DIR/runtime"
SQUID_DIR="$RUNTIME_DIR/squid"
CICAP_DIR="$RUNTIME_DIR/c-icap"
PORTAL_DIR="$RUNTIME_DIR/portal"

mkdir -p "$SQUID_DIR/certs" "$SQUID_DIR/cache" "$SQUID_DIR/log" "$CICAP_DIR" "$PORTAL_DIR"

if [[ ! -f "$SQUID_DIR/certs/proxy-root-ca.key" ]]; then
  echo "[1/7] Generating local Root CA for TLS inspection (demo)."
  docker run --rm -v "$SQUID_DIR/certs:/certs" alpine/openssl:latest genrsa -out /certs/proxy-root-ca.key 4096
  docker run --rm -v "$SQUID_DIR/certs:/certs" alpine/openssl:latest req -new -x509 -days 3650 -key /certs/proxy-root-ca.key -out /certs/proxy-root-ca.crt -subj "/C=RU/O=Company Proxy/CN=Company Proxy Root CA"
fi

cat > "$SQUID_DIR/squid.conf" <<'SQUIDCONF'
http_port 3128 ssl-bump cert=/etc/squid/certs/proxy-root-ca.crt key=/etc/squid/certs/proxy-root-ca.key generate-host-certificates=on dynamic_cert_mem_cache_size=32MB

acl step1 at_step SslBump1
ssl_bump peek step1
ssl_bump bump all

acl blocked_hdr rep_header Content-Disposition -i attachment
acl blocked_mime rep_mime_type -i ^application/ ^image/ ^video/ ^audio/
http_reply_access deny blocked_hdr
http_reply_access deny blocked_mime

icap_enable on
icap_send_client_ip on
icap_send_client_username on
icap_service service_resp respmod_precache icap://c-icap:1344/squidclamav bypass=0
adaptation_access service_resp allow all

request_header_access Proxy-Authorization deny all
via off
forwarded_for delete
access_log stdio:/var/log/squid/access.log
cache_log /var/log/squid/cache.log
cache deny all
SQUIDCONF

cat > "$CICAP_DIR/c-icap.conf" <<'CICAPCONF'
PidFile /var/run/c-icap/c-icap.pid
CommandsSocket /var/run/c-icap/c-icap.ctl
Timeout 300
MaxServers 30
StartServers 5
MinSpareThreads 10
MaxSpareThreads 20
ThreadsPerChild 20
Port 1344
User c-icap
Group c-icap
ServerAdmin admin@localhost
ServerName c-icap-server

Service squidclamav squidclamav.so
ServiceAlias avscan squidclamav
Module common

Include /etc/c-icap/squidclamav.conf
CICAPCONF

cat > "$CICAP_DIR/squidclamav.conf" <<'CLAMCONF'
clamd_ip clamd
clamd_port 3310
maxsize 100M
stream_max_length 100M
CLAMCONF

cat > "$RUNTIME_DIR/docker-compose.yml" <<'COMPOSE'
services:
  squid:
    image: ubuntu/squid:latest
    container_name: corp-squid
    depends_on:
      - c-icap
    ports:
      - "3128:3128"
    volumes:
      - ./squid/squid.conf:/etc/squid/squid.conf:ro
      - ./squid/certs:/etc/squid/certs:rw
      - ./squid/cache:/var/spool/squid
      - ./squid/log:/var/log/squid

  c-icap:
    build:
      context: ../cicap
    container_name: corp-c-icap
    depends_on:
      - clamd
    ports:
      - "1344:1344"
    volumes:
      - ./c-icap/c-icap.conf:/etc/c-icap/c-icap.conf:ro
      - ./c-icap/squidclamav.conf:/etc/c-icap/squidclamav.conf:ro

  clamd:
    image: clamav/clamav:latest
    container_name: corp-clamd
    ports:
      - "3310:3310"

  portal:
    image: python:3.11-slim
    container_name: corp-portal
    working_dir: /app
    command: sh -c "pip install flask && python quarantine_server.py"
    ports:
      - "8080:8080"
    volumes:
      - ../storage/quarantine_server.py:/app/quarantine_server.py:ro
      - ./portal:/data
COMPOSE

echo "[2/7] Initializing squid SSL DB inside container image."
INIT_CMD='if [ -x /usr/lib/squid/security_file_certgen ]; then /usr/lib/squid/security_file_certgen -c -s /certs/ssl_db -M 32MB; elif [ -x /usr/lib/squid/cert_tool ]; then /usr/lib/squid/cert_tool -c -s /certs/ssl_db -M 32MB; else echo "ERROR: no squid cert tool found" >&2; exit 1; fi'
docker run --rm -v "$SQUID_DIR/certs:/certs" ubuntu/squid:latest sh -lc "$INIT_CMD"

echo "[3/7] Starting services with docker compose."
(cd "$RUNTIME_DIR" && docker compose up -d --build)

echo "[4/7] Verifying services."
(cd "$RUNTIME_DIR" && docker compose ps)

echo "[5/7] Proxy endpoint: http://<server-ip>:3128"
echo "[6/7] ICAP endpoint: icap://<server-ip>:1344/squidclamav"
echo "[7/7] Portal/API: http://localhost:8080"
echo

echo "IMPORTANT: Install runtime/squid/certs/proxy-root-ca.crt into managed Android trust store via MDM."
echo "IMPORTANT: Block QUIC and enforce proxy/VPN from MDM policy."
