FROM debian:12-slim

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       c-icap squidclamav ca-certificates \
    && rm -rf /var/lib/apt/lists/*

EXPOSE 1344
CMD ["c-icap", "-N", "-f", "/etc/c-icap/c-icap.conf"]
