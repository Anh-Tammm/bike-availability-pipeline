FROM apache/airflow:3.3.2

# dbt in its own virtualenv: dbt and Airflow have conflicting dependencies
COPY dbt/requirements.txt /tmp/requirements-dbt.txt
RUN python -m venv /opt/airflow/dbt-venv \
 && /opt/airflow/dbt-venv/bin/pip install --no-cache-dir -r /tmp/requirements-dbt.txt
