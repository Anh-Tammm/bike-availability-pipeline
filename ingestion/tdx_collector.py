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
from datetime import UTC, datetime
from pathlib import Path

from dotenv import load_dotenv

from common import build_path, make_session, setup_logging, store

TOKEN_URL = "https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token"
API_BASE = "https://tdx.transportdata.tw/api/basic/v2/Bike"
FEEDS = {
    "availability": "Availability/City/{city}",
    "station": "Station/City/{city}",
}

# Local file by default; set TDX_TOKEN_CACHE=gs://bucket/path.json on Cloud Run
# (the container disk is wiped after each execution).
TOKEN_CACHE = os.environ.get(
    "TDX_TOKEN_CACHE", str(Path.home() / ".cache" / "bike-pipeline" / "tdx_token.json")
)


def _gcs_blob():
    from google.cloud import storage
    return storage.Blob.from_string(TOKEN_CACHE, client=storage.Client(project=os.environ.get("GCP_PROJECT_ID")))


def read_cache() -> dict | None:
    """Return the cached token, or None if missing/unreadable (we then fetch a new one)."""
    try:
        if TOKEN_CACHE.startswith("gs://"):
            return json.loads(_gcs_blob().download_as_bytes())
        path = Path(TOKEN_CACHE)
        return json.loads(path.read_text()) if path.exists() else None
    except Exception as exc:  # noqa: BLE001 - a broken cache must never stop the collection
        log.warning("Token cache unreadable, a new token will be requested: %s", exc)
        return None


def write_cache(content: dict) -> None:
    data = json.dumps(content)
    if TOKEN_CACHE.startswith("gs://"):
        _gcs_blob().upload_from_string(data, content_type="application/json")
        return
    path = Path(TOKEN_CACHE)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.touch(mode=0o600, exist_ok=True)
    path.write_text(data)


def clear_cache() -> None:
    try:
        if TOKEN_CACHE.startswith("gs://"):
            _gcs_blob().delete()
        else:
            Path(TOKEN_CACHE).unlink(missing_ok=True)
    except Exception as exc:  # noqa: BLE001 - best effort, the next run fetches a new token anyway
        log.warning("Could not clear the token cache: %s", exc)

log = logging.getLogger("tdx_collector")


def get_token(session) -> str:
    """Return a valid access token, reusing the cached one while it is valid.

    Tokens last ~24h: caching avoids one auth request per run, as TDX recommends.
    """
    cached = read_cache()
    if cached and cached["expires_at"] > time.time() + 600:  # 10-minute safety margin
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
    write_cache({"access_token": body["access_token"], "expires_at": time.time() + body["expires_in"]})
    log.info("New TDX token obtained (valid %.0f h)", body["expires_in"] / 3600)
    return body["access_token"]

def fetch_feed(session, token: str, city: str, feed: str) -> bytes:
    """Call one TDX endpoint and check the payload looks like a station list."""
    url = f"{API_BASE}/{FEEDS[feed].format(city=city)}"
    resp = session.get(url, params={"$format": "JSON"},
                       headers={"authorization": f"Bearer {token}"}, timeout=30)
    if resp.status_code == 401:
        clear_cache()  # force a fresh token on next run
    resp.raise_for_status()
    try:
        payload = json.loads(resp.content)
    except ValueError:  # not JSON at all (e.g. an HTML maintenance page)
        payload = None
    if not isinstance(payload, list) or not payload or "StationUID" not in payload[0]:
        raise ValueError(
            f"Unexpected TDX payload from {url} (HTTP {resp.status_code}): {resp.text[:300]!r}"
        )
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

    collected_at = datetime.now(UTC)
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
