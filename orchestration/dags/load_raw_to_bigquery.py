"""Load raw collector snapshots from GCS into BigQuery, then run dbt.

Every hour, for each feed, loads the files of that hour
(gs://<bucket>/<prefix>/dt=YYYY-MM-DD/hh=HH/*.json.gz) into raw.<table>.

Idempotent: files are loaded into a temporary table, then a MERGE on
source_file inserts only the files not loaded yet. Re-running an hour
(retry, backfill, clear) never creates duplicates.

After the loads, the most recent run only (not every catch-up run)
executes dbt build and dbt source freshness.
"""
import gzip
import io
import json
import os
from datetime import datetime, timedelta, timezone

from airflow.providers.standard.operators.bash import BashOperator
from airflow.providers.standard.operators.latest_only import LatestOnlyOperator
from airflow.sdk import dag, get_current_context, task
from airflow.timetables.interval import CronDataIntervalTimetable

FEEDS = [
    {"prefix": "gbfs/velib/station_status", "table": "velib_station_status"},
    {"prefix": "gbfs/velib/station_information", "table": "velib_station_information"},
    {"prefix": "tdx/hsinchu/availability", "table": "youbike_availability"},
    {"prefix": "tdx/hsinchu/station", "table": "youbike_station"},
]
RAW_SCHEMA = [
    ("source_file", "STRING"),
    ("collected_at", "TIMESTAMP"),
    ("loaded_at", "TIMESTAMP"),
    ("payload", "JSON"),
]

# dbt writes artifacts to /tmp so it never clobbers your local dbt/target folder
DBT_CMD = (
    "cd /opt/airflow/dbt && /opt/airflow/dbt-venv/bin/dbt {cmd} "
    "--target-path /tmp/dbt-target --log-path /tmp/dbt-logs"
)


@dag(
    # Explicit hourly data intervals [HH:00, HH+1:00) in UTC, aligned with the hh= folders
    schedule=CronDataIntervalTimetable("0 * * * *", timezone="UTC"),
    start_date=datetime(2026, 11, 14, 5, tzinfo=timezone.utc),  # first collected files
    catchup=True,  # when Airflow restarts, every missed hour is loaded
    max_active_runs=4,
    default_args={
        "retries": 4,
        "retry_delay": timedelta(minutes=2),
        "retry_exponential_backoff": True,   # 2, 4, 8, 16 min between attempts
        "max_retry_delay": timedelta(minutes=30),
    },
    tags=["raw", "bigquery", "dbt"],
    doc_md=__doc__,
)
def load_raw_to_bigquery():

    @task
    def load_feed(feed: dict) -> int:
        # Imports and env vars inside the task: this code runs on the worker only,
        # not in the dag-processor (which parses this file often and has no GCP access)
        from google.cloud import bigquery, storage

        ctx = get_current_context()
        start, end = ctx["data_interval_start"], ctx["data_interval_end"]
        if end - start != timedelta(hours=1):
            raise ValueError(f"Expected a 1-hour interval, got {start} -> {end}")

        project = os.environ["GOOGLE_CLOUD_PROJECT"]
        bucket = os.environ["GCS_BUCKET"]
        prefix = f"{feed['prefix']}/dt={start:%Y-%m-%d}/hh={start:%H}/"

        blobs = list(storage.Client(project=project).list_blobs(bucket, prefix=prefix))
        if not blobs:
            print(f"No files under gs://{bucket}/{prefix}")
            return 0

        # Build one NDJSON line per file
        loaded_at = datetime.now(timezone.utc).isoformat()
        lines = []
        for blob in blobs:
            name = blob.name.rsplit("/", 1)[-1]
            collected_at = datetime.strptime(name, "%Y%m%dT%H%M%SZ.json.gz").replace(tzinfo=timezone.utc)
            lines.append(json.dumps({
                "source_file": f"gs://{bucket}/{blob.name}",
                "collected_at": collected_at.isoformat(),
                "loaded_at": loaded_at,
                "payload": json.loads(gzip.decompress(blob.download_as_bytes())),
            }))

        bq = bigquery.Client(project=project)
        target = f"{project}.raw.{feed['table']}"
        tmp = f"{project}.raw._tmp_{feed['table']}_{start:%Y%m%d%H}"
        load_config = bigquery.LoadJobConfig(
            schema=[bigquery.SchemaField(n, t, mode="REQUIRED") for n, t in RAW_SCHEMA],
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
            write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        )
        merge_sql = f"""
            MERGE `{target}` T
            USING `{tmp}` S
            ON T.source_file = S.source_file
               AND T.collected_at >= @start AND T.collected_at < @end
            WHEN NOT MATCHED THEN INSERT ROW
        """
        merge_config = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter("start", "TIMESTAMP", start),
            bigquery.ScalarQueryParameter("end", "TIMESTAMP", end),
        ])

        try:
            data = io.BytesIO("\n".join(lines).encode("utf-8"))
            bq.load_table_from_file(data, tmp, job_config=load_config).result()
            job = bq.query(merge_sql, job_config=merge_config)
            job.result()
            inserted = job.num_dml_affected_rows or 0
        finally:
            bq.delete_table(tmp, not_found_ok=True)  # never leave temporary tables behind

        print(f"{feed['table']}: {len(lines)} files found, {inserted} new rows inserted")
        return inserted

    # Dynamic task mapping: one task instance per feed, visible separately in the UI
    loads = load_feed.expand(feed=FEEDS)

    # During a catch-up, only the most recent run transforms the data
    latest_only = LatestOnlyOperator(task_id="latest_only")

    dbt_build = BashOperator(
        task_id="dbt_build",
        bash_command=DBT_CMD.format(cmd="build"),
        max_active_tis_per_dag=1,  # never two dbt runs on the same tables
    )

    # Detects a stopped collection (Cloud Run); fails without blocking dbt_build
    dbt_freshness = BashOperator(
        task_id="dbt_source_freshness",
        bash_command=DBT_CMD.format(cmd="source freshness"),
        max_active_tis_per_dag=1,
    )

    loads >> latest_only >> [dbt_build, dbt_freshness]


load_raw_to_bigquery()
