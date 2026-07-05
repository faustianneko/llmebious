LISP ?= sbcl

build:
	$(LISP) --load nmebious.asd \
		--eval '(ql:quickload :nmebious)' \
		--eval '(asdf:make :nmebious)' \
		--eval '(quit)'

run:
	$(LISP) --load nmebious.asd \
	     	--eval '(ql:quickload :nmebious)' \
	     	--eval '(in-package :nmebious)' \
	     	--eval '(main t)'

# ----------------------------------------------------------------------------
# Production Docker deployment
#
# Pick the compose CLI available on the host (v2 "docker compose" or v1
# "docker-compose"), and always pass BOTH compose files so nobody has to
# remember the -f flags.
# ----------------------------------------------------------------------------
DC   := $(shell docker compose version >/dev/null 2>&1 && echo "docker compose" || echo "docker-compose")
PROD := $(DC) -f docker-compose.yml -f docker-compose.prod.yml

.PHONY: deploy prod-up prod-down prod-ps prod-logs backup

deploy: ## Pull latest code and rebuild + redeploy the prod stack
	git pull
	$(PROD) up -d --build

prod-up: ## (Re)build and start the prod stack without pulling
	$(PROD) up -d --build

prod-down: ## Stop the prod stack (volumes/data are kept)
	$(PROD) down

prod-ps: ## Show prod container status
	$(PROD) ps

prod-logs: ## Follow prod logs
	$(PROD) logs -f --tail=100

backup: ## Snapshot DB + uploads to $$BACKUP_DIR (default ~/backups)
	./scripts/backup.sh
