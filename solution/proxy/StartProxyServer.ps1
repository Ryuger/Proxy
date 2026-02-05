Param(
    [switch]$SkipCertGeneration
)

$ErrorActionPreference = 'Stop'

# Free/open-source stack:
# - Squid (GPLv2)
# - c-icap (LGPL)
# - ClamAV (GPLv2)

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RuntimeDir = Join-Path $RootDir 'runtime'
$SquidDir = Join-Path $RuntimeDir 'squid'
$CertsDir = Join-Path $SquidDir 'certs'
$CacheDir = Join-Path $SquidDir 'cache'
$LogDir = Join-Path $SquidDir 'log'
$CIcapDir = Join-Path $RuntimeDir 'c-icap'
$PortalDir = Join-Path $RuntimeDir 'portal'

New-Item -ItemType Directory -Force -Path $CertsDir, $CacheDir, $LogDir, $CIcapDir, $PortalDir | Out-Null

$CaKeyPath = Join-Path $CertsDir 'proxy-root-ca.key'
$CaCrtPath = Join-Path $CertsDir 'proxy-root-ca.crt'

if (-not $SkipCertGeneration -and -not (Test-Path $CaKeyPath)) {
    Write-Host '[1/6] Generating local Root CA for TLS inspection (demo) via OpenSSL container...'

    docker run --rm -v "${CertsDir}:/certs" alpine/openssl:latest sh -lc "\
      openssl genrsa -out /certs/proxy-root-ca.key 4096 && \
      openssl req -new -x509 -days 3650 \
        -key /certs/proxy-root-ca.key \
        -out /certs/proxy-root-ca.crt \
        -subj '/C=RU/O=Company Proxy/CN=Company Proxy Root CA'"
}

$squidConfig = @'
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
'@
Set-Content -Path (Join-Path $SquidDir 'squid.conf') -Value $squidConfig -Encoding UTF8

$ciCapConfig = @'
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
'@
Set-Content -Path (Join-Path $CIcapDir 'c-icap.conf') -Value $ciCapConfig -Encoding UTF8

$squidClam = @'
clamd_ip clamd
clamd_port 3310
maxsize 100M
stream_max_length 100M
'@
Set-Content -Path (Join-Path $CIcapDir 'squidclamav.conf') -Value $squidClam -Encoding UTF8

$compose = @'
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
    image: moul/icap:latest
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
'@
Set-Content -Path (Join-Path $RuntimeDir 'docker-compose.yml') -Value $compose -Encoding UTF8

Write-Host '[2/6] Initializing squid SSL DB...'
docker run --rm -v "${CertsDir}:/certs" ubuntu/squid:latest /usr/lib/squid/security_file_certgen -c -s /certs/ssl_db -M 32MB | Out-Null

Write-Host '[3/6] Starting services with docker compose...'
Push-Location $RuntimeDir
try {
    docker compose up -d
}
finally {
    Pop-Location
}

Write-Host '[4/6] Proxy started on :3128'
Write-Host '[5/6] ICAP AV service on :1344'
Write-Host '[6/6] Portal/API on http://localhost:8080'
Write-Host ''
Write-Host 'IMPORTANT: Install runtime/squid/certs/proxy-root-ca.crt into managed Android trust store via MDM.'
Write-Host 'IMPORTANT: Block QUIC and enforce proxy/VPN from MDM policy.'
