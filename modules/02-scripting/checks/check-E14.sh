# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres
#
# check-E14.sh — M02-E14 : tester ses scripts Bash avec bats
# À lancer depuis adm01. Les tests de TON dépôt sont lancés dans un environnement coupé
# de Proxmox (HOME jetable, aucun fichier d'accès, proxy HTTPS inexistant) : s'ils passent,
# c'est qu'ils ne dépendent pas du vrai lab. Lecture seule (dossiers temporaires de bats).

title "M02-E14 — Tester ses scripts Bash avec bats"
require_cmd bats git

_m02_r="${WB_SRC:-$HOME/src}/outils"

check_output "bats-core 1.13 sur adm01" '^Bats 1\.(1[3-9]|[2-9][0-9])' bats --version
check_cmd "dossier tests/bats versionné" bash -c '[[ -n "$(git -C "$1" ls-files tests/bats)" ]]' _ "$_m02_r"
check_cmd "des tests visent lib/ms-commun.sh" bash -c 'grep -lq "ms-commun" "$1"/tests/bats/*.bats' _ "$_m02_r"
check_cmd "des tests visent bin/ms-snapshot" bash -c 'grep -lq "ms-snapshot" "$1"/tests/bats/*.bats' _ "$_m02_r"
check_output "au moins 20 tests bats" '^([2-9][0-9]|[1-9][0-9]{2,})$' bats --count "$_m02_r/tests/bats"
check_output "les tests sont fusionnés dans main (GitLab)" '\.bats"' \
  gitlab_api "projects/plateforme%2Foutils/repository/tree?path=tests/bats&ref=main&per_page=100"

_m02_tmp="$(mktemp -d)"
check_cmd "tous les tests passent, sans accès au vrai Proxmox" bash -c '
  cd "$1" && env -u PVE_API_URL -u PVE_NODE -u PVE_TOKEN_ID -u PVE_TOKEN_SECRET -u PVE_CACERT \
    HOME="$2" MS_PVE_ENV_FILE="$2/absent.env" https_proxy=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 \
    no_proxy= NO_PROXY= bats tests/bats </dev/null >/dev/null 2>&1' _ "$_m02_r" "$_m02_tmp"
rm -rf -- "${_m02_tmp:?}"
