.PHONY: dev down logs migration migrate places-migration places-migrate devices-migration devices-migrate

dev:
	docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up --build

down:
	docker compose -f docker-compose.yaml -f docker-compose.dev.yaml down


logs:
	docker compose logs -f

migration:
	docker compose exec auth uv run alembic revision --autogenerate -m "$(m)"

migrate:
	docker compose exec auth uv run alembic upgrade head

places-migration:
	docker compose exec places uv run alembic revision --autogenerate -m "$(m)"

places-migrate:
	docker compose exec places uv run alembic upgrade head

devices-migration:
	docker compose exec devices uv run alembic revision --autogenerate -m "$(m)"

devices-migrate:
	docker compose exec devices uv run alembic upgrade head
