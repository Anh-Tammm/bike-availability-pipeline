"""Collect GBFS feeds and store raw snapshots (gzip JSON) in GCS or locally.

Usage:
    python ingestion/gbfs_collector.py --system velib --feeds station_status
    python ingestion/gbfs_collector.py --system velib --feeds station_status --local-dir data
"""
import argparse
import gzip
import json
import logging
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import requests
from dotenv import load_dotenv
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

SYSTEMS = {
    "velib": "https://velib-metropole-opendata.smovengo.cloud/opendata/Velib_Metropole/gbfs.json",
}

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("gbfs_collector")


def make_session() -> requests.Session:
    """HTTP session with automatic retries on transient errors."""
    retry = Retry(
        total=3,
        backoff_factor=2,  # waits 2s, 4s, 8s between attempts
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET"],
    )
    session = requests.Session()
    session.mount("https://", HTTPAdapter(max_retries=retry))
    session.headers["User-Agent"] = "bike-availability-pipeline (student portfolio project)"
    return session


def discover_feeds(session: requests.Session, gbfs_url: str) -> dict[str, str]:
    """Read the GBFS discovery file and return {feed_name: feed_url}."""
    resp = session.get(gbfs_url, timeout=30)
    resp.raise_for_status()
    data = resp.json()["data"]
    lang = "fr" if "fr" in data else next(iter(data))
    return {feed["name"]: feed["url"] for feed in data[lang]["feeds"]}


def build_path(system: str, feed: str, ts: datetime) -> str:
    """Hive-style partitioned path, in UTC."""
    return f"gbfs/{system}/{feed}/dt={ts:%Y-%m-%d}/hh={ts:%H}/{ts:%Y%m%dT%H%M%SZ}.json.gz"


def fetch_feed(session: requests.Session, url: str) -> bytes:
    """Download a feed and check it is valid GBFS JSON before storing it."""
    resp = session.get(url, timeout=30)
    resp.raise_for_status()
    payload = json.loads(resp.content)  # fails loudly on HTML error pages
    if "stations" not in payload.get("data", {}):
        raise ValueError(f"Unexpected GBFS payload from {url}")
    n_stations = len(payload["data"].get("stations", []))
    log.info("Fetched %s: %d stations, %d bytes", url.rsplit("/", 1)[-1], n_stations, len(resp.content))
    return resp.content  # keep the raw bytes exactly as received


def store_local(base_dir: str, path: str, data: bytes) -> None:
    target = Path(base_dir) / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    log.info("Stored locally: %s", target)


def store_gcs(bucket_name: str, project: str, path: str, data: bytes) -> None:
    from google.cloud import storage  # imported here so local mode needs no GCP auth

    blob = storage.Client(project=project).bucket(bucket_name).blob(path)
    # if_generation_match=0: never overwrite an existing file
    blob.upload_from_string(data, content_type="application/gzip", if_generation_match=0)
    log.info("Stored in GCS: gs://%s/%s", bucket_name, path)


def main() -> int:
    load_dotenv()
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--system", required=True, choices=SYSTEMS.keys())
    parser.add_argument("--feeds", nargs="+", default=["station_status"])
    parser.add_argument("--local-dir", help="Write to this local folder instead of GCS (for testing)")
    args = parser.parse_args()

    collected_at = datetime.now(timezone.utc)
    session = make_session()

    try:
        feeds = discover_feeds(session, SYSTEMS[args.system])
        for feed in args.feeds:
            if feed not in feeds:
                raise KeyError(f"Feed '{feed}' not found. Available: {sorted(feeds)}")
            data = gzip.compress(fetch_feed(session, feeds[feed]))
            path = build_path(args.system, feed, collected_at)
            if args.local_dir:
                store_local(args.local_dir, path, data)
            else:
                store_gcs(os.environ["GCS_BUCKET"], os.environ["GCP_PROJECT_ID"], path, data)
    except Exception:
        log.exception("Collection failed")
        return 1  # non-zero exit code: the orchestrator will flag the run as failed
    return 0


if __name__ == "__main__":
    sys.exit(main())
