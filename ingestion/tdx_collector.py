"""Collect YouBike data from TDX (Taiwan MOTC) and store raw snapshots (gzip JSON).

Feeds:
    availability  real-time bikes / docks per station
    station       names, positions, capacity (changes rarely)

Usage:
    python ingestion/tdx_collector.py --city Hsinchu --feeds availability
    python ingestion/tdx_collector.py --city Hsinchu --feeds availability station --local-dir data

Requires TDX_CLIENT_ID and TDX_CLIENT_SECRET in .env (free tier: ~3,000 calls/month).
"""
import argparse
import gzip
import json
import logging
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from dotenv import load_dotenv

from common import build_path, make_session, setup_logging, store

TOKEN_URL = "https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token"
API_BASE = "https://tdx.transportdata.tw/api/basic/v2/Bike"
FEEDS = {
    "availability": "Availability/City/{city}",
    "station": "Station/City/{city}",
}
TOKEN_CACHE = Path.home() / ".cache" / "bike-pipeline" / "tdx_token.json"

log = logging.getLogger("tdx_collector")


def get_token(session) -> str:
    """Return a valid access token, reusing the cached one while it is valid.

    Tokens last ~24h: caching avoids one auth request per run, as TDX recommends.
    """
    if TOKEN_CACHE.exists():
        cached = json.loads(TOKEN_CACHE.read_text())
        if cached["expires_at"] > time.time() + 600:  # 10-minute safety margin
            return cached["access_token"]

    resp = session.post(
        TOKEN_URL,
        data={
            "grant_type": "client_credentials",
            "client_id": os.environ["TDX_CLIENT_ID"],
            "client_secret": os.environ["TDX_CLIENT_SECRET"],
        },
        timeout=30,
    )
    resp.raise_for_status()
    body = resp.json()

    TOKEN_CACHE.parent.mkdir(parents=True, exist_ok=True)
    TOKEN_CACHE.touch(mode=0o600, exist_ok=True)  # readable by you only
    TOKEN_CACHE.write_text(json.dumps({
        "access_token": body["access_token"],
        "expires_at": time.time() + body["expires_in"],
    }))
    log.info("New TDX token obtained (valid %.0f h)", body["expires_in"] / 3600)
    return body["access_token"]


def fetch_feed(session, token: str, city: str, feed: str) -> bytes:
    """Call one TDX endpoint and check the payload looks like a station list."""
    url = f"{API_BASE}/{FEEDS[feed].format(city=city)}"
    resp = session.get(url, params={"$format": "JSON"},
                       headers={"authorization": f"Bearer {token}"}, timeout=30)
    if resp.status_code == 401:
        TOKEN_CACHE.unlink(missing_ok=True)  # force a fresh token on next run
    resp.raise_for_status()
    payload = json.loads(resp.content)
    if not isinstance(payload, list) or not payload or "StationUID" not in payload[0]:
        raise ValueError(f"Unexpected TDX payload from {url}")
    log.info("Fetched %s/%s: %d stations, %d bytes", city, feed, len(payload), len(resp.content))
    return resp.content


def main() -> int:
    load_dotenv()
    setup_logging()
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--city", default="Hsinchu")
    parser.add_argument("--feeds", nargs="+", default=["availability"], choices=FEEDS.keys())
    parser.add_argument("--local-dir", help="Write to this local folder instead of GCS (for testing)")
    args = parser.parse_args()

    collected_at = datetime.now(timezone.utc)
    session = make_session(total_retries=2)  # failed calls may count against the quota
    try:
        token = get_token(session)
        for feed in args.feeds:
            data = gzip.compress(fetch_feed(session, token, args.city, feed))
            store(build_path("tdx", args.city.lower(), feed, collected_at), data, args.local_dir)
    except Exception:
        log.exception("Collection failed")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
