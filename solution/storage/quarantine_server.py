from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict

from flask import Flask, jsonify, render_template_string, request

DATA_ROOT = Path(os.getenv("QUARANTINE_DATA", "/data"))
FILES_DIR = DATA_ROOT / "files"
META_FILE = DATA_ROOT / "metadata.json"

FILES_DIR.mkdir(parents=True, exist_ok=True)
if not META_FILE.exists():
    META_FILE.write_text("{}", encoding="utf-8")

app = Flask(__name__)


def load_meta() -> Dict[str, dict]:
    return json.loads(META_FILE.read_text(encoding="utf-8"))


def save_meta(meta: Dict[str, dict]) -> None:
    META_FILE.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def clamav_scan(path: Path) -> str:
    clamscan = shutil.which("clamscan")
    if not clamscan:
        return "PENDING_NO_ENGINE"

    run = subprocess.run(
        [clamscan, "--no-summary", str(path)],
        capture_output=True,
        text=True,
    )
    output = (run.stdout + run.stderr).upper()
    if "FOUND" in output:
        return "INFECTED"
    if run.returncode == 0:
        return "CLEAN"
    return "SCAN_ERROR"


@app.post("/api/v1/ingest")
def ingest_file():
    file_obj = request.files.get("file")
    user_id = request.form.get("user_id", "unknown")
    source_url = request.form.get("source_url", "unknown")

    if not file_obj or not file_obj.filename:
        return jsonify({"error": "file is required"}), 400

    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        file_obj.save(tmp.name)
        temp_path = Path(tmp.name)

    file_hash = sha256_file(temp_path)
    target_path = FILES_DIR / file_hash
    temp_path.replace(target_path)

    status = clamav_scan(target_path)
    now = datetime.now(timezone.utc).isoformat()

    meta = load_meta()
    meta[file_hash] = {
        "filename": file_obj.filename,
        "size": target_path.stat().st_size,
        "sha256": file_hash,
        "status": status,
        "user_id": user_id,
        "source_url": source_url,
        "created_at": now,
    }
    save_meta(meta)

    return jsonify(meta[file_hash]), 201


@app.get("/api/v1/files")
def list_files():
    return jsonify(load_meta())


@app.get("/")
def portal():
    entries = list(load_meta().values())
    entries.sort(key=lambda e: e["created_at"], reverse=True)
    return render_template_string(
        """
        <h1>Quarantine Portal</h1>
        <p>Просмотр загруженных через proxy файлов. Локальная выдача клиенту не делается.</p>
        <table border="1" cellpadding="6">
          <tr><th>User</th><th>Filename</th><th>SHA256</th><th>Status</th><th>Source</th><th>Created(UTC)</th></tr>
          {% for x in entries %}
          <tr>
            <td>{{ x.user_id }}</td>
            <td>{{ x.filename }}</td>
            <td><code>{{ x.sha256 }}</code></td>
            <td>{{ x.status }}</td>
            <td>{{ x.source_url }}</td>
            <td>{{ x.created_at }}</td>
          </tr>
          {% endfor %}
        </table>
        """,
        entries=entries,
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
