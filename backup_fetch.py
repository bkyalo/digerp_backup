#!/usr/bin/env python3
"""Download the nightly digerp database backup.

The backup itself is produced by a separate server on its own schedule
(embedded in the filename as backup_hhmm, e.g. "0300"). This script is
meant to be triggered by Windows Task Scheduler afterwards, e.g. 03:30,
to give that server time to finish. It's not always done by then, so
this polls the backup URL every poll_interval_seconds for up to
poll_duration_minutes before giving up.

Config comes from config.json (copy config.example.json and fill it in).
"""

from __future__ import annotations

import base64
import json
import logging
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path

FOLDER = Path(__file__).resolve().parent
CONFIG_PATH = FOLDER / "config.json"
LOG_PATH = FOLDER / "backup_fetch.log"

REQUIRED_KEYS = ["site_url", "company_id", "db_name", "backup_prefix"]


def load_config() -> dict:
    if not CONFIG_PATH.exists():
        sys.exit(
            f"Missing {CONFIG_PATH}. Copy config.example.json to config.json "
            "and fill in your site details."
        )
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    missing = [key for key in REQUIRED_KEYS if not config.get(key) and config.get(key) != 0]
    if missing:
        sys.exit(f"config.json is missing: {', '.join(missing)}")
    config.setdefault("download_dir", "backups")
    config.setdefault("backup_hhmm", "0300")
    config.setdefault("poll_duration_minutes", 5)
    config.setdefault("poll_interval_seconds", 20)
    config.setdefault("basic_auth_user", "")
    config.setdefault("basic_auth_password", "")
    return config


def build_url_and_filename(config: dict, date_str: str) -> tuple[str, str]:
    filename = (
        f"{config['backup_prefix']}_{config['db_name']}_{config['company_id']}"
        f"_{date_str}_{config['backup_hhmm']}.sql.gz"
    )
    site_url = config["site_url"].rstrip("/")
    url = f"{site_url}/company/{config['company_id']}/backup/{filename}"
    return url, filename


def build_request(url: str, config: dict) -> urllib.request.Request:
    req = urllib.request.Request(url)
    if config["basic_auth_user"]:
        credentials = f"{config['basic_auth_user']}:{config['basic_auth_password']}"
        token = base64.b64encode(credentials.encode("utf-8")).decode("ascii")
        req.add_header("Authorization", f"Basic {token}")
    return req


def try_download(url: str, dest_path: Path, config: dict) -> bool:
    """Return True if the backup was downloaded, False if not ready yet (404)."""
    req = build_request(url, config)
    tmp_path = dest_path.with_suffix(dest_path.suffix + ".part")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp, open(tmp_path, "wb") as out:
            while True:
                chunk = resp.read(1024 * 64)
                if not chunk:
                    break
                out.write(chunk)
    except urllib.error.HTTPError as exc:
        tmp_path.unlink(missing_ok=True)
        if exc.code == 404:
            return False
        raise
    except urllib.error.URLError:
        tmp_path.unlink(missing_ok=True)
        raise

    tmp_path.replace(dest_path)
    return True


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=[logging.FileHandler(LOG_PATH, encoding="utf-8"), logging.StreamHandler(sys.stdout)],
    )

    config = load_config()
    download_dir = FOLDER / config["download_dir"]
    download_dir.mkdir(parents=True, exist_ok=True)

    now = datetime.now()
    date_str = now.strftime("%Y%m%d")
    url, filename = build_url_and_filename(config, date_str)
    dest_path = download_dir / filename

    if dest_path.exists() and dest_path.stat().st_size > 0:
        logging.info("Backup already downloaded: %s", dest_path)
        return

    deadline = now + timedelta(minutes=config["poll_duration_minutes"])
    interval = config["poll_interval_seconds"]

    logging.info("Polling for %s (deadline %s)", url, deadline.strftime("%H:%M:%S"))

    attempt = 0
    while True:
        attempt += 1
        try:
            found = try_download(url, dest_path, config)
        except (urllib.error.HTTPError, urllib.error.URLError) as exc:
            logging.warning("Attempt %d failed: %s", attempt, exc)
            found = False

        if found:
            logging.info("Downloaded backup to %s (attempt %d)", dest_path, attempt)
            return

        if datetime.now() >= deadline:
            logging.error(
                "Backup not available at %s after %d attempt(s); giving up.", url, attempt
            )
            sys.exit(1)

        logging.info("Not ready yet (attempt %d); retrying in %ds.", attempt, interval)
        time.sleep(interval)


if __name__ == "__main__":
    main()
