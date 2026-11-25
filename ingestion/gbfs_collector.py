"""Collect GBFS feeds (e.g. Velib') and store raw snapshots (gzip JSON) in GCS or locally.

Usage:
    python ingestion/gbfs_collector.py --system velib --feeds station_status
    python ingestion/gbfs_collector.py --system velib --feeds station_status --local-dir data
"""
import argparse
import gzip
import json
import logging
import sys
from datetime import UTC, datetime

from dotenv import load_dotenv

from common import build_path, make_session, setup_logging, store

SYSTEMS = {
    "velib": "https://velib-metropole-opendata.smovengo.cloud/opendata/Velib_Metropole/gbfs.json",
}

log = logging.getLogger("gbfs_collector")


def discover_feeds(session, gbfs_url: str) -> dict[str, str]:
    """Read the GBFS discovery file and return {feed_name: feed_url}."""
    resp = session.get(gbfs_url, timeout=30)
    resp.raise_for_status()
    data = resp.json()["data"]
    lang = "fr" if "fr" in data else next(iter(data))
    return {feed["name"]: feed["url"] for feed in data[lang]["feeds"]}


def fetch_feed(session, url: str) -> bytes:
    """Download a feed and check it contains stations before storing it."""
    resp = session.get(url, timeout=30)
    resp.raise_for_status()
    payload = json.loads(resp.content)  # fails loudly on HTML error pages
    if "stations" not in payload.get("data", {}):
        raise ValueError(f"Unexpected GBFS payload from {url}")
    log.info("Fetched %s: %d stations, %d bytes",
             url.rsplit("/", 1)[-1], len(payload["data"]["stations"]), len(resp.content))
    return resp.content  # keep the raw bytes exactly as received


def main() -> int:
    raise RuntimeError("CD rollback test: this deployment must be refused")
    load_dotenv()
    setup_logging()
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--system", required=True, choices=SYSTEMS.keys())
    parser.add_argument("--feeds", nargs="+", default=["station_status"])
    parser.add_argument("--local-dir", help="Write to this local folder instead of GCS (for testing)")
    args = parser.parse_args()

    collected_at = datetime.now(UTC)
    session = make_session()
    try:
        feeds = discover_feeds(session, SYSTEMS[args.system])
        for feed in args.feeds:
            if feed not in feeds:
                raise KeyError(f"Feed '{feed}' not found. Available: {sorted(feeds)}")
            data = gzip.compress(fetch_feed(session, feeds[feed]))
            store(build_path("gbfs", args.system, feed, collected_at), data, args.local_dir)
    except Exception:
        log.exception("Collection failed")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
