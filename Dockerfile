FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir oci-cli

WORKDIR /app

COPY retry.sh /app/retry.sh
COPY scripts /app/scripts

RUN chmod +x /app/retry.sh /app/scripts/bin/*.sh

CMD ["/app/retry.sh"]
