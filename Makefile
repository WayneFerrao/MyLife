# MyLife — common workflows
# Run `make help` to see all targets.

COMPOSE := docker compose

.PHONY: help up down status logs logs-rag logs-openclaw \
        rebuild-rag restart-openclaw restart-all health \
        setup network backup restore reset-vectors clean

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ── Start / Stop ─────────────────────────────────────────────────────

up: ## Start services (profiles controlled by COMPOSE_PROFILES in .env)
	$(COMPOSE) up -d

down: ## Stop all services (including profiled ones)
	$(COMPOSE) --profile ollama --profile immich down

# ── Status / Logs ────────────────────────────────────────────────────

status: ## Show status of all containers
	$(COMPOSE) --profile ollama --profile immich ps -a

logs: ## Tail logs for all running services
	$(COMPOSE) logs -f

logs-rag: ## Tail RAG service logs
	$(COMPOSE) logs -f rag

logs-openclaw: ## Tail OpenClaw logs
	$(COMPOSE) logs -f openclaw-gateway

# ── Rebuild / Restart ────────────────────────────────────────────────

rebuild-rag: ## Rebuild RAG image and restart (after code changes in rag/src/)
	$(COMPOSE) up -d --build --force-recreate rag

restart-openclaw: ## Recreate OpenClaw (picks up .env and config changes)
	$(COMPOSE) up -d --force-recreate openclaw-gateway

restart-all: ## Restart all core services
	$(COMPOSE) restart

# ── Health ───────────────────────────────────────────────────────────

health: ## Check health of all service endpoints
	@printf "Ollama:   " && curl -sf http://localhost:11434/api/tags > /dev/null 2>&1 \
		&& echo "ok" || echo "unreachable (install: https://ollama.com/download)"
	@printf "Qdrant:   " && curl -sf http://localhost:6333/readyz 2>/dev/null \
		&& echo "" || echo "unreachable"
	@printf "RAG:      " && curl -sf http://localhost:18790/health 2>/dev/null \
		|| echo "unreachable"
	@printf "\nOpenClaw: " && curl -sf http://localhost:18789/healthz > /dev/null 2>&1 \
		&& echo "ok" || echo "unreachable"

# ── Setup ────────────────────────────────────────────────────────────

setup: ## Run first-time setup (generates keys, configures services)
	bash setup.sh

network: ## Create shared Docker network (idempotent)
	@docker network inspect mylife-shared >/dev/null 2>&1 || \
		(docker network create mylife-shared && echo "Created mylife-shared network")

# ── Data Management ──────────────────────────────────────────────────

backup: ## Snapshot Qdrant vector data (timestamped tarball)
	@mkdir -p backups
	tar -czf backups/qdrant-$$(date +%Y%m%d-%H%M%S).tar.gz -C qdrant qdrant_data
	@echo "Backup saved to backups/"

restore: ## Restore Qdrant data from a backup tarball (usage: make restore FILE=backups/qdrant-XXX.tar.gz)
	@if [ -z "$(FILE)" ]; then echo "Usage: make restore FILE=backups/qdrant-YYYYMMDD-HHMMSS.tar.gz"; \
		echo ""; echo "Available backups:"; ls -1 backups/qdrant-*.tar.gz 2>/dev/null || echo "  (none)"; exit 1; fi
	@[ -f "$(FILE)" ] || { echo "Error: $(FILE) not found"; exit 1; }
	@echo "This will replace current Qdrant data with $(FILE)."
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	$(COMPOSE) stop qdrant
	rm -rf qdrant/qdrant_data
	tar -xzf $(FILE) -C qdrant/
	$(COMPOSE) up -d qdrant
	@echo "Restored from $(FILE). Waiting for Qdrant to start..."
	@sleep 3 && $(COMPOSE) ps qdrant

reset-vectors: ## Delete and recreate the Qdrant collection (loses all stored notes)
	@echo "This will delete all stored notes from Qdrant."
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	@COLLECTION=$$(grep '^COLLECTION_NAME=' rag/.env 2>/dev/null | cut -d= -f2 || echo "notes"); \
		QDRANT_KEY=$$(grep '^QDRANT_API_KEY=' rag/.env 2>/dev/null | cut -d= -f2); \
		HEADER=""; [ -n "$$QDRANT_KEY" ] && HEADER="-H api-key:$$QDRANT_KEY"; \
		echo "Deleting collection '$$COLLECTION'..."; \
		curl -sf -X DELETE $$HEADER http://localhost:6333/collections/$$COLLECTION; \
		echo "\nCollection deleted. It will be recreated on next RAG startup."; \
		echo "Restart RAG: make rebuild-rag"

# ── Cleanup ──────────────────────────────────────────────────────────

clean: ## Stop all services and remove volumes (DESTRUCTIVE)
	@echo "WARNING: This will stop all services and remove Docker volumes."
	@echo "Qdrant data, Immich data, and model caches will be DELETED."
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	$(COMPOSE) --profile ollama --profile immich down -v
