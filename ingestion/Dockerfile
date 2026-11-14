FROM python:3.13-slim

# Logs flushed immediately (visible in Cloud Logging), no .pyc files
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# Dependencies first: this layer is cached as long as requirements.txt doesn't change
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Never run as root
RUN useradd --create-home appuser
USER appuser

ENTRYPOINT ["python"]
CMD ["gbfs_collector.py", "--help"]
