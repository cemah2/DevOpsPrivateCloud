# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres
#
# check-E18.sh — M02-E18 : tester medictl avec pytest sans toucher à Proxmox
# À lancer depuis adm01. Les tests de TON dépôt sont lancés coupés de Proxmox (HOME jetable,
# aucun fichier d'accès, proxy HTTPS inexistant, variables PVE_* retirées) ; ni cache pytest
# ni fichier de couverture ne sont écrits dans le clone.

title "M02-E18 — Tester medictl avec pytest sans toucher à Proxmox"
require_cmd git

_m02_r="${WB_SRC:-$HOME/src}/outils"
_m02_py="$_m02_r/.venv/bin/python"
_m02_tmp="$(mktemp -d)"

# _m02_pytest ARGS... — pytest de l'environnement du projet, isolé du lab
_m02_pytest() {
  (cd "$_m02_r" && env -u PVE_API_URL -u PVE_NODE -u PVE_TOKEN_ID -u PVE_TOKEN_SECRET -u PVE_CACERT \
    HOME="$_m02_tmp" MEDICTL_ENV_FILE="$_m02_tmp/absent.env" COVERAGE_FILE="$_m02_tmp/.coverage" \
    https_proxy=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 no_proxy= NO_PROXY= \
    "$_m02_py" -m pytest -p no:cacheprovider "$@" </dev/null 2>&1)
}

check_cmd "environnement du projet présent (.venv, uv sync)" test -x "$_m02_py"
check_cmd "tests/python versionné" bash -c '[[ -n "$(git -C "$1" ls-files tests/python)" ]]' _ "$_m02_r"
check_output "au moins 30 tests collectés" '(^|[^0-9])([3-9][0-9]|[1-9][0-9]{2,}) tests? collected' \
  _m02_pytest --collect-only -q
check_cmd "des tests vérifient les refus des garde-fous (code 3)" \
  bash -c 'grep -rEq "exit_code *== *3|RefusGardeFou" "$1"/tests/python' _ "$_m02_r"
check_cmd "des tests simulent l'API HTTP (responses) ou injectent un faux client" \
  bash -c 'grep -rEq "import responses|responses\.|monkeypatch" "$1"/tests/python' _ "$_m02_r"
check_output "tous les tests passent, coupés de Proxmox" ' passed' _m02_pytest -q
check_cmd "aucun test en échec ou en erreur" bash -c '! grep -Eq "[0-9]+ (failed|error)" <<<"$1"' _ "$(_m02_pytest -q || true)"
check_output "couverture de medictl mesurée : au moins 70 %" '^TOTAL.* (7[0-9]|8[0-9]|9[0-9]|100)%$' \
  _m02_pytest -q --cov=medictl --cov-report=term
check_output "les tests sont fusionnés dans main (GitLab)" 'test_' \
  gitlab_api "projects/plateforme%2Foutils/repository/tree?path=tests/python&ref=main&per_page=100"
rm -rf -- "${_m02_tmp:?}"
