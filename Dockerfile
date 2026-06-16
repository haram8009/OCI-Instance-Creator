FROM python:3.12.10-slim-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
    oci-cli==3.86.0 \
    'discord.py>=2.4,<3'

WORKDIR /app

COPY retry.sh /app/retry.sh
COPY scripts /app/scripts

RUN chmod +x /app/retry.sh /app/scripts/bin/*.sh /app/scripts/bin/*.py

CMD ["/app/retry.sh"]
