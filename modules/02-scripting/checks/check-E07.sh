# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres ($1…)
#
# check-E07.sh — M02-E07 : Un environnement Python moderne avec uv
# À lancer depuis adm01. Lecture seule : « uv lock --check » ne réécrit pas uv.lock,
# ruff tourne sans cache, l'environnement .venv n'est pas resynchronisé.

title "M02-E07 — Un environnement Python moderne avec uv"
require_cmd uv git python3 jq

_m02_r="${WB_SRC:-$HOME/src}/outils"

# _m02_toml FILTRE_JQ — interroge pyproject.toml converti en JSON (tomllib de Python 3.13)
_m02_toml() {
  python3 -c 'import json, sys, tomllib; print(json.dumps(tomllib.load(open(sys.argv[1], "rb"))))' \
    "$_m02_r/pyproject.toml" 2>/dev/null | jq -r "$1" 2>/dev/null
}

check_output "uv 0.12 sur adm01" '^uv 0\.(1[2-9]|[2-9][0-9])\.' uv --version

# --- Fichiers du projet -----------------------------------------------------------------
for _m02_f in pyproject.toml uv.lock .python-version src/medictl/__init__.py src/medictl/cli.py; do
  check_cmd "$_m02_f versionné" git -C "$_m02_r" ls-files --error-unmatch "$_m02_f"
done
check_cmd "l'environnement .venv n'est pas versionné" \
  bash -c '[[ -z $(git -C "$1" ls-files .venv) ]]' _ "$_m02_r"
check_cmd "l'environnement .venv est ignoré par Git" git -C "$_m02_r" check-ignore -q .venv
check_output ".python-version : 3.13" '^3\.13' cat "$_m02_r/.python-version"

# --- pyproject.toml ---------------------------------------------------------------------------
check_output "projet nommé medictl" '^medictl$' _m02_toml '.project.name'
check_output "Python 3.13 minimum (requires-python)" '^>= ?3\.13' _m02_toml '.project."requires-python"'
check_output "dépendances : typer, proxmoxer et requests" '^3$' \
  _m02_toml '[.project.dependencies[] | ascii_downcase | select(test("^(typer|proxmoxer|requests)\\b"))] | length'
check_output "groupe de développement : pytest, responses et ruff" '^3$' \
  _m02_toml '[."dependency-groups".dev[]? | ascii_downcase | select(test("^(pytest|responses|ruff)\\b"))] | length'
check_output "commande medictl déclarée (project.scripts)" '^medictl\.' _m02_toml '.project.scripts.medictl // empty'
check_output "construction par uv_build (projet empaqueté)" '^uv_build$' _m02_toml '."build-system"."build-backend"'
check_output "ruff : liste de règles explicite (lint.select)" '^[1-9]' _m02_toml '.tool.ruff.lint.select | length'
check_output "uv : Python du système uniquement (python-preference)" '^only-system$' \
  _m02_toml '.tool.uv."python-preference" // empty'

# --- Verrou et environnement -----------------------------------------------------------------
check_cmd "uv.lock à jour par rapport à pyproject.toml (uv lock --check)" \
  bash -c 'cd "$1" && uv lock --check >/dev/null 2>&1' _ "$_m02_r"
check_output "l'environnement .venv repose sur le Python de Debian (/usr/bin)" '^home = /usr/bin$' \
  cat "$_m02_r/.venv/pyvenv.cfg"
check_output "medictl --version répond depuis l'environnement du projet" '^medictl [0-9]+\.[0-9]+\.[0-9]+' \
  "$_m02_r/.venv/bin/medictl" --version
check_cmd "ruff check : aucun défaut sur src/" \
  bash -c 'cd "$1" && .venv/bin/ruff check --no-cache src >/dev/null' _ "$_m02_r"
check_cmd "ruff format : src/ déjà formaté" \
  bash -c 'cd "$1" && .venv/bin/ruff format --no-cache --check src >/dev/null' _ "$_m02_r"
check_cmd ".pre-commit-config.yaml : hooks ruff (ruff-pre-commit)" \
  grep -q 'astral-sh/ruff-pre-commit' "$_m02_r/.pre-commit-config.yaml"
