# infra

> Docker Compose stack, Makefile, and all shared configuration for running PlaceBrain on a single host.

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](./LICENSE)
![Docker Compose](https://img.shields.io/badge/docker--compose-v2-2496ED.svg)
![Traefik](https://img.shields.io/badge/Traefik-v3-24A1C1.svg)
![EMQX](https://img.shields.io/badge/EMQX-5.9-4398F3.svg)
![Kafka](https://img.shields.io/badge/Kafka-4.0--KRaft-231F20.svg)

This is the one thing you clone to stand up the entire PlaceBrain platform on your laptop. It contains **only** infra — no application code. The service repositories are clones side-by-side; compose points at them with `../backend/*` and `../frontend` build contexts.

## Role in PlaceBrain

PlaceBrain is an open-source IoT platform for smart buildings. See the [organization profile](https://github.com/PlaceBrain) for the full architecture and the list of all eight repositories.

- This repo **does not contain** runtime data. Compose writes to `../var/*` (one directory up), which is deliberately outside every git repo.
- Services are built from sibling directories (`../backend/auth`, `../frontend`, etc.) so contributing to a single service does not require a full monorepo checkout.

## What's inside

```
infra/
├── docker-compose.yaml          base stack: postgres, redis, kafka (KRaft), auth, places,
│                                devices, collector, gateway, emqx, frontend, traefik
├── docker-compose.dev.yaml      dev overlay: volume-mounted src for hot reload, Vite dev server,
│                                exposed DB/Redis/EMQX ports
├── docker-compose.prod.yaml     prod overlay: Traefik HTTPS + Let's Encrypt, TLS MQTT
├── Makefile                     dev / down / logs / migrations for auth, places, devices
├── .env.example                 POSTGRES_USER / POSTGRES_PASSWORD (copy to .env)
└── config/
    ├── traefik/                 traefik.yaml, traefik.dev.yaml, dynamic/ (file provider)
    ├── nginx/default.conf       SPA config for the frontend prod image
    ├── emqx/emqx.conf           MQTT listener, HTTP authn/acl webhooks, Kafka bridge rules
    ├── kafka/server.properties
    ├── postgresql/Dockerfile    postgres:17 + timescaledb-2 extension
    └── postgres-init/           *.sh scripts run on first DB init (places_db, devices_db, telemetry_db)
```

## Quickstart

You need Docker Desktop (or Docker Engine + Compose v2).

```bash
# 1. Create a workspace and clone every repo side-by-side.
mkdir placebrain && cd placebrain
git clone https://github.com/PlaceBrain/infra.git
git clone https://github.com/PlaceBrain/contracts.git
git clone https://github.com/PlaceBrain/frontend.git
mkdir backend && cd backend
for r in auth places gateway devices collector; do
  git clone "https://github.com/PlaceBrain/$r.git"
done
cd ..

# 2. Configure the shared Postgres credentials.
cd infra
cp .env.example .env
# edit .env: set POSTGRES_USER and POSTGRES_PASSWORD

# 3. Each service needs its own .env. For the default compose setup:
#    - Postgres hostname is placebrain-database, DSN is postgresql+asyncpg://<user>:<pass>@placebrain-database:5432/<svc>_db
#    - All URLs use the Docker-network hostnames (placebrain-kafka, placebrain-redis, placebrain-emqx)
#    See each service's .env.example for the full list.
#    The auth service JWT__SECRET must equal gateway's JWT_SECRET.

# 4. Bring the stack up.
make dev
```

After a minute or two `docker compose ps` should show all 11 containers healthy. Then:

- Web UI: <http://localhost>
- Swagger: <http://localhost/docs>
- Traefik dashboard (dev overlay only): <http://localhost:8080>
- EMQX dashboard (dev overlay only): <http://localhost:18083>

## Services in the stack

| Service | Port (host) | Health check | Depends on |
|---|---|---|---|
| traefik | 80 / 443 / 1883 / 8080 | — | — (runs always, discovers via Docker socket) |
| postgres (custom build, Timescale enabled) | 5432 (dev) | `pg_isready` | — |
| redis | 6379 (dev) | `redis-cli ping` | — |
| kafka (KRaft, single-broker) | 9092 (dev) / 19092 (in-cluster) | broker API versions | — |
| kafka-init | — | — | kafka (healthy) — creates all topics, exits |
| auth | — | tcp 50051 | postgres |
| places | — | tcp 50052 | postgres, kafka |
| devices | — | tcp 50053 | postgres, redis, kafka |
| collector | — | tcp 50054 | postgres, redis, kafka, emqx |
| gateway | — (proxied via Traefik) | tcp 8000 | auth, places, devices |
| emqx | 1883 (TCP) / 8083 (WS) / 18083 (dashboard, dev) | `emqx ctl status` | gateway, kafka |
| frontend | — (Vite 5173 dev, Nginx 80 prod, both proxied via Traefik) | HTTP probe | — |

## Routing (Traefik)

- `PathPrefix(\`/api/\`) && !PathPrefix(\`/api/internal/\`)` → `gateway:8000`
- `PathPrefix(\`/docs\`)` or `Path(\`/openapi.json\`)` → `gateway:8000`
- `PathPrefix(\`/mqtt\`)` → `emqx:8083` (WebSocket)
- `HostSNI(\`*\`)` on entrypoint `mqtt` (TCP :1883) → `emqx:1883`
- `PathPrefix(\`/\`)` (priority 1) → frontend (Vite dev server or Nginx)

The `/api/internal/*` prefix is blocked externally and reachable only from inside the Docker network — EMQX calls those webhooks directly at `gateway:8000`.

## Kafka topics

The broker runs with `auto.create.topics.enable=false` (see `config/kafka/server.properties`) so every topic must be declared up front. The `kafka-init` service is a one-shot container that runs `kafka-topics.sh --create --if-not-exists` for each topic once the broker is healthy, then exits.

Consumers (`places`, `devices`, `collector`) wait for `kafka-init` to exit successfully via `depends_on: { kafka-init: { condition: service_completed_successfully } }`. This avoids a cold-start race where a consumer subscribes to a topic that does not yet exist, which would otherwise surface as noisy "unknown topic" warnings.

To add a new topic, add another `kafka-topics.sh --create --if-not-exists ...` line to the `kafka-init` service in `docker-compose.yaml`. Existing topics are idempotent — re-running the stack is safe.

## Makefile targets

```
make dev                    # docker compose up --build (base + dev overlay)
make down                   # docker compose down
make logs                   # docker compose logs -f
make migration m="desc"     # alembic revision --autogenerate in auth
make migrate                # alembic upgrade head in auth
make places-migration m=""  # same for places
make places-migrate
make devices-migration m="" # same for devices
make devices-migrate
```

Migrations run automatically on service startup (`alembic upgrade head` in each service's CMD). The Make targets above are only for **generating** new revisions.

## Data persistence

`docker-compose.yaml` writes to `../var/*` relative to this repo, which resolves to `placebrain/var/` in the workspace layout above:

```
placebrain/
├── infra/            (this repo)
├── var/              (runtime state — not in any git repo)
│   ├── postgresql/   Postgres + TimescaleDB data
│   ├── kafka/        Kafka logs
│   ├── redis/        Redis AOF/RDB
│   └── gateway/      Generated openapi.json
└── backend/ frontend/ contracts/ workflows/   (service repos)
```

On a fresh checkout docker creates these directories automatically.

## Production overlay

```bash
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml up -d
```

Adds: HTTPS on `:443` with Let's Encrypt (HTTP-01), TLS MQTT on the `mqtt` entrypoint, no dev port forwarding. Still a single-host setup — for anything bigger you want an orchestrator.

## License

Apache License 2.0 — see [LICENSE](./LICENSE).
