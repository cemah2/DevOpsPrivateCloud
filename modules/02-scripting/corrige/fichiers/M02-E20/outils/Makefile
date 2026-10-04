# Makefile — équivalent du Taskfile.yml, pour comparaison (M02-E20).
# Le projet utilise Task ; ce fichier montre ce que Make apporte (dépendances
# entre FICHIERS, présent partout) et ce qu'il coûte (tabulations, .PHONY,
# un shell par ligne, variables à double niveau d'évaluation).
#
#   make lint | make test | make build | make install | make ci | make clean

SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help
MAKEFLAGS += --warn-undefined-variables --no-builtin-rules

REPORTS := rapports
SCRIPTS_SH = $(shell shfmt -f bin lib tests | sort)
SOURCES_PY := $(shell find src -name '*.py')

.PHONY: help setup lint lint-sh lint-py test test-bats test-py install ci clean

help: ## Liste les cibles
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

# Cible fichier : refaite seulement si pyproject.toml ou uv.lock sont plus récents.
.venv/pyvenv.cfg: pyproject.toml uv.lock
	uv sync --locked
	@touch $@

setup: .venv/pyvenv.cfg ## Environnement Python selon uv.lock

lint-sh: ## ShellCheck et shfmt (réglages : .shellcheckrc, .editorconfig)
	shellcheck $(SCRIPTS_SH)
	shfmt -d $(SCRIPTS_SH)

lint-py: setup ## ruff
	uv run --locked ruff check .
	uv run --locked ruff format --check .

lint: lint-sh lint-py ## Toutes les analyses statiques

test-bats: ## Tests bats
	mkdir -p $(REPORTS)
	bats --report-formatter junit --output $(REPORTS) tests/bats

test-py: setup ## Tests pytest avec couverture
	mkdir -p $(REPORTS)
	uv run --locked pytest --junitxml=$(REPORTS)/junit-pytest.xml --cov=medictl --cov-report=term-missing

test: test-bats test-py ## Tous les tests

# Le paquet est un vrai fichier : make compare les dates et ne reconstruit que si besoin.
dist/.construit: pyproject.toml uv.lock README.md $(SOURCES_PY) | setup
	rm -rf dist
	uv build
	@touch $@

build: dist/.construit ## Paquet medictl dans dist/
.PHONY: build

PREFIX ?= /usr/local

install: ## Copie figée de bin/ et lib/ dans $(PREFIX) (sudo), medictl (uv tool)
	git diff --quiet HEAD -- bin lib || { echo "bin/ ou lib/ non commités" >&2; exit 1; }
	sudo install -d -m 755 $(PREFIX)/bin $(PREFIX)/lib
	sudo install -m 644 lib/ms-commun.sh $(PREFIX)/lib/ms-commun.sh
	sudo install -m 755 bin/ms-* $(PREFIX)/bin/
	uv tool install --force --reinstall --from $(CURDIR) medictl

ci: ## Enchaînement de la CI
	$(MAKE) lint
	$(MAKE) test
	$(MAKE) build

clean: ## Produits de construction et rapports
	rm -rf dist $(REPORTS) .pytest_cache .ruff_cache .coverage
