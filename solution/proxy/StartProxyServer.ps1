Param(
    [switch]$SkipCertGeneration
)

$ErrorActionPreference = 'Stop'

function Require-Command([string]$name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $name"
    }
}

function Invoke-DockerChecked([string[]]$Args) {
    & docker @Args
    if ($LASTEXITCODE -ne 0) {
        throw "Docker command failed: docker $($Args -join ' ')"
    }
}

Require-Command docker

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
    Write-Host '[1/7] Generating local Root CA for TLS inspection (demo)...'
    Invoke-DockerChecked @('run', '--rm', '-v', "${CertsDir}:/certs", 'alpine/openssl:latest', 'genrsa', '-out', '/certs/proxy-root-ca.key', '4096')
    Invoke-DockerChecked @('run', '--rm', '-v', "${CertsDir}:/certs", 'alpine/openssl:latest', 'req', '-new', '-x509', '-days', '3650', '-key', '/certs/proxy-root-ca.key', '-out', '/certs/proxy-root-ca.crt', '-subj', '/C=RU/O=Company Proxy/CN=Company Proxy Root CA')
} elseif (-not (Test-Path $CaCrtPath)) {
    throw "CA certificate not found at $CaCrtPath. Run without -SkipCertGeneration or place certificate files manually."
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
'@
Set-Content -Path (Join-Path $RuntimeDir 'docker-compose.yml') -Value $compose -Encoding UTF8

Write-Host '[2/7] Initializing squid SSL DB...'
$initCmd = "if [ -x /usr/lib/squid/security_file_certgen ]; then /usr/lib/squid/security_file_certgen -c -s /certs/ssl_db -M 32MB; elif [ -x /usr/lib/squid/cert_tool ]; then /usr/lib/squid/cert_tool -c -s /certs/ssl_db -M 32MB; else echo 'ERROR: no squid cert tool found' >&2; exit 1; fi"
Invoke-DockerChecked @('run', '--rm', '-v', "${CertsDir}:/certs", 'ubuntu/squid:latest', 'sh', '-lc', $initCmd)

Write-Host '[3/7] Starting services with docker compose...'
Push-Location $RuntimeDir
try {
    & docker compose up -d --build
    if ($LASTEXITCODE -ne 0) {
        throw 'docker compose up failed'
    }
}
finally {
    Pop-Location
}

Write-Host '[4/7] Verifying running containers...'
Push-Location $RuntimeDir
try {
    & docker compose ps
}
finally {
    Pop-Location
}

Write-Host '[5/7] Proxy endpoint: http://<server-ip>:3128'
Write-Host '[6/7] ICAP endpoint: icap://<server-ip>:1344/squidclamav'
Write-Host '[7/7] Portal/API: http://localhost:8080'
Write-Host ''
Write-Host 'IMPORTANT: Install runtime/squid/certs/proxy-root-ca.crt into managed Android trust store via MDM.'
Write-Host 'IMPORTANT: Block QUIC and enforce proxy/VPN from MDM policy.'
