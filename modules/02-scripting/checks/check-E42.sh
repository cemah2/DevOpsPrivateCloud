# shellcheck shell=bash
# check-E42.sh — M02-E42 « Panne : l'environnement Python est cassé » : état sain.
# medictl installé par « uv tool » fonctionne et c'est bien lui qui est appelé ; aucun autre
# medictl visible de l'interpréteur système ; l'environnement du projet ~/src/outils importe
# ses dépendances et son propre code, et les tests passent. Lecture seule : uv run --no-sync
# (aucune synchronisation), pas de cache pytest ni de bytecode écrits.

title "M02-E42 — Environnements Python sains"
require_cmd uv python3

_m02_e42_proj="${WB_SRC:-$HOME/src}/outils"

_m02_e42_lanceur_uv() {
  local m outils
  m="$(command -v medictl)" || return 1
  outils="$(uv tool dir 2>/dev/null)" || return 1
  [[ "$(readlink -f "$m")" == "$(readlink -f "$outils")"/medictl/* ]]
}

# medictl --version affiche la version que uv tool dit avoir installée.
_m02_e42_version() {
  local v
  v="$(uv tool list 2>/dev/null | sed -nE 's/^medictl v([0-9][^ ]*).*/\1/p')"
  [[ -n "$v" ]] && medictl --version 2>&1 | grep -qF -- "$v"
}

_m02_e42_pas_de_doublon() {
  (cd / && python3 -c 'import importlib.util, sys; sys.exit(0 if importlib.util.find_spec("medictl") is None else 1)')
}

_m02_e42_imports() {
  (cd "$_m02_e42_proj" && PYTHONDONTWRITEBYTECODE=1 uv run --no-sync python -c '
import sys
import medictl, typer, proxmoxer, requests
sys.exit(0 if "/src/medictl/" in medictl.__file__ else 1)')
}

# Aucun fichier .pth de l'environnement n'ajoute un chemin hors du projet et de l'environnement.
_m02_e42_pth() {
  local f l
  for f in "$_m02_e42_proj"/.venv/lib/python3*/site-packages/*.pth; do
    [[ -f "$f" ]] || continue
    while IFS= read -r l; do
      [[ "$l" == /* ]] || continue
      [[ "$l" == "$_m02_e42_proj"/* || "$l" == "$_m02_e42_proj" ]] || return 1
    done <"$f"
  done
}

_m02_e42_tests() {
  (cd "$_m02_e42_proj" && PYTHONDONTWRITEBYTECODE=1 timeout 300 uv run --no-sync pytest -q -p no:cacheprovider)
}

check_cmd "medictl présent dans le PATH" command -v medictl
check_cmd "medictl appelé est celui installé par uv tool" _m02_e42_lanceur_uv
check_cmd "medictl --version répond la version installée par uv tool" _m02_e42_version
check_cmd "aucun autre paquet medictl visible de l'interpréteur système (site utilisateur)" _m02_e42_pas_de_doublon
check_cmd "projet outils : environnement .venv présent" test -d "$_m02_e42_proj/.venv"
check_cmd "projet outils : dépendances et code du projet importables (sans resynchroniser)" _m02_e42_imports
check_cmd "projet outils : aucun fichier .pth n'ajoute de chemin étranger" _m02_e42_pth
check_cmd "projet outils : la suite pytest passe" _m02_e42_tests
