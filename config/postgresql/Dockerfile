FROM postgres:17-bookworm

RUN apt-get update && apt-get install -y \
    gnupg lsb-release curl \
  && echo "deb https://packagecloud.io/timescale/timescaledb/debian/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/timescaledb.list \
  && curl -sL https://packagecloud.io/timescale/timescaledb/gpgkey | gpg --dearmor -o /etc/apt/trusted.gpg.d/timescaledb.gpg \
  && apt-get update \
  && apt-get install -y timescaledb-2-postgresql-17 \
  && apt-get clean && rm -rf /var/lib/apt/lists/*
