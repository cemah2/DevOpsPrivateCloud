# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres
#
# check-E20.sh — M02-E20 : Taskfile (et Makefile), les tâches du projet
# À lancer depuis adm01. Le contrôle lance « task lint » et « task test » dans ton clone :
# ils n'écrivent que dans .venv, rapports/ et les caches, tous ignorés par Git.

title "M02-E20 — Taskfile (et Makefile) : les tâches du projet"
require_cmd task make git

_m02_r="${WB_SRC:-$HOME/src}/outils"

check_output "Task 3.x sur adm01" '(^|[^0-9])3\.[0-9]+' task --version
check_cmd "Taskfile.yml et Makefile versionnés" git -C "$_m02_r" ls-files --error-unmatch Taskfile.yml Makefile
_m02_liste="$(cd "$_m02_r" && task --list 2>/dev/null || true)"
for _m02_t in lint test build install install:systeme install:dev; do
  check_output "tâche « $_m02_t » décrite (task --list)" "^\\* $_m02_t:([[:space:]]|\$)" printf '%s\n' "$_m02_liste"
done
check_cmd "task lint réussit" bash -c 'cd "$1" && task lint </dev/null >/dev/null 2>&1' _ "$_m02_r"
check_cmd "task test réussit" bash -c 'cd "$1" && task test </dev/null >/dev/null 2>&1' _ "$_m02_r"
check_cmd "task test produit des rapports JUnit (rapports/*.xml)" \
  bash -c 'compgen -G "$1/rapports/*.xml" >/dev/null' _ "$_m02_r"
check_cmd "build à jour : « task --status build » ne demande pas de reconstruction" \
  bash -c 'cd "$1" && task --status build >/dev/null 2>&1' _ "$_m02_r"
check_cmd "un paquet medictl construit est présent (dist/*.whl)" \
  bash -c 'compgen -G "$1/dist/medictl-*.whl" >/dev/null' _ "$_m02_r"
check_cmd "Makefile : make -n lint et make -n test sont valides" \
  bash -c 'cd "$1" && make -n lint >/dev/null 2>&1 && make -n test >/dev/null 2>&1' _ "$_m02_r"

# --- Installation figée --------------------------------------------------------------------
check_cmd "/usr/local/bin/ms-snapshot installé (fichier, pas lien vers le clone)" \
  bash -c '[[ -f /usr/local/bin/ms-snapshot && ! -L /usr/local/bin/ms-snapshot ]]'
check_cmd "/usr/local/lib/ms-commun.sh installé" test -f /usr/local/lib/ms-commun.sh
check_cmd "la copie installée trouve sa bibliothèque (ms-snapshot --help)" \
  bash -c '/usr/local/bin/ms-snapshot --help </dev/null >/dev/null 2>&1'
check_output "medictl installé comme outil uv (uv tool list)" '^medictl ' uv tool list
