"""Shared helpers for collectors: HTTP session, partitioned paths, raw storage."""
import logging
import os
from datetime import datetime
from pathlib import Path

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

log = logging.getLogger("common")


def setup_logging() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")


def make_session(total_retries: int = 3) -> requests.Session:
    """HTTP session with automatic retries on transient errors (GET only)."""
    retry = Retry(
        total=total_retries,
        backoff_factor=2,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET"],
    )
    session = requests.Session()
    session.mount("https://", HTTPAdapter(max_retries=retry))
    session.headers["User-Agent"] = "bike-availability-pipeline (student portfolio project)"
    return session


def build_path(source: str, system: str, feed: str, ts: datetime) -> str:
    """Hive-style partitioned path, in UTC."""
    return f"{source}/{system}/{feed}/dt={ts:%Y-%m-%d}/hh={ts:%H}/{ts:%Y%m%dT%H%M%SZ}.json.gz"


def store(path: str, data: bytes, local_dir: str | None = None) -> None:
    """Write raw bytes locally (tests) or to GCS (never overwrites an existing object)."""
    if local_dir:
        target = Path(local_dir) / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        log.info("Stored locally: %s", target)
        return

    from google.cloud import storage  # imported here so local mode needs no GCP auth

    bucket = os.environ["GCS_BUCKET"]
    blob = storage.Client(project=os.environ["GCP_PROJECT_ID"]).bucket(bucket).blob(path)
    blob.upload_from_string(data, content_type="application/gzip", if_generation_match=0)
    log.info("Stored in GCS: gs://%s/%s", bucket, path)
