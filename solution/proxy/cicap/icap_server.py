#!/usr/bin/env python3
"""
Minimal ICAP server for Squid integration in environments where c-icap packages
are unavailable in base distro repos.

Implements:
- OPTIONS
- RESPMOD / REQMOD -> 204 No Content

This keeps the proxy pipeline working and can be extended with real clamd scan.
"""

from __future__ import annotations

import socketserver


class IcapHandler(socketserver.StreamRequestHandler):
    protocol = "ICAP/1.0"

    def _read_headers(self) -> tuple[str, dict[str, str]]:
        req_line = self.rfile.readline().decode("utf-8", errors="replace").strip()
        headers: dict[str, str] = {}
        while True:
            line = self.rfile.readline().decode("utf-8", errors="replace")
            if not line or line in ("\r\n", "\n"):
                break
            if ":" in line:
                k, v = line.split(":", 1)
                headers[k.strip().lower()] = v.strip()
        return req_line, headers

    def _send(self, payload: str) -> None:
        self.wfile.write(payload.encode("utf-8"))

    def handle(self) -> None:
        req_line, headers = self._read_headers()
        if not req_line:
            return

        method = req_line.split(" ", 1)[0].upper()
        req_id = headers.get("x-client-ip", "unknown")

        if method == "OPTIONS":
            self._send(
                f"{self.protocol} 200 OK\r\n"
                "Methods: RESPMOD, REQMOD\r\n"
                "Service: Minimal Python ICAP\r\n"
                "Preview: 0\r\n"
                "Transfer-Preview: *\r\n"
                "Allow: 204\r\n"
                "Encapsulated: null-body=0\r\n"
                f"ISTag: \"pyicap-{req_id}\"\r\n"
                "\r\n"
            )
            return

        if method in {"RESPMOD", "REQMOD"}:
            self._send(
                f"{self.protocol} 204 No Content\r\n"
                "Encapsulated: null-body=0\r\n"
                f"ISTag: \"pyicap-{req_id}\"\r\n"
                "\r\n"
            )
            return

        self._send(
            f"{self.protocol} 405 Method Not Allowed\r\n"
            "Encapsulated: null-body=0\r\n"
            "\r\n"
        )


class ThreadedIcapServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True


if __name__ == "__main__":
    with ThreadedIcapServer(("0.0.0.0", 1344), IcapHandler) as server:
        server.serve_forever()
