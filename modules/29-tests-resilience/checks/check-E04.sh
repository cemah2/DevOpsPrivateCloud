# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E04.sh — M29-E04 : Testinfra : tester les rôles Ansible sur les VMs
# À lancer depuis adm01. Lecture seule : fichiers de plateforme/ansible sur main, derniers jobs de la CI
# (API GitLab). Les tests eux-mêmes tournent dans la CI (runner01) : le check vérifie qu'ils existent,
# qu'ils testent quelque chose, et qu'un job Testinfra a réussi récemment.

# shellcheck source=_m29-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-decouverte.sh"

title "M29-E04 — Testinfra : tester les rôles Ansible sur les VMs"
require_cmd jq curl

_m29d_e04_dir="tests/infra"
for _m29d_e04_f in conftest.py test_durcissement.py test_node_exporter.py test_alloy.py test_chrony.py; do
  _m29d_e04_c="$(_m29d_contenu "$_M29D_P_ANSIBLE" "$_m29d_e04_dir/$_m29d_e04_f")"
  if [[ "$_m29d_e04_f" == conftest.py ]]; then
    check_cmd "plateforme/ansible : $_m29d_e04_dir/conftest.py (fixtures partagées)" bash -c '[[ "$1" == *"pytest.fixture"* ]]' _ "$_m29d_e04_c"
    continue
  fi
  _m29d_e04_n="$(grep -cE '^\s*def test_' <<<"$_m29d_e04_c" || true)"
  check_cmd "plateforme/ansible : $_m29d_e04_dir/$_m29d_e04_f, au moins 4 tests (${_m29d_e04_n})" \
    bash -c '(( ${1:-0} >= 4 ))' _ "$_m29d_e04_n"
  # Un test qui ne regarde que des fichiers ne prouve pas que le service marche : au moins un
  # contrôle d'état (service, socket, commande).
  check_cmd "$_m29d_e04_f : contrôle l'état réel (service, socket ou commande), pas seulement des fichiers" \
    bash -c 'grep -Eq "host\.(service|socket|run|check_output|sysctl|mount_point)\(" <<<"$1"' _ "$_m29d_e04_c"
  _m29d_e04_m="${_m29d_e04_f#test_}"
  _m29d_e04_m="${_m29d_e04_m%.py}"
  check_cmd "$_m29d_e04_f : marqueur pytest « $_m29d_e04_m »" \
    bash -c 'grep -Eq "pytest\.mark\.$2\b" <<<"$1"' _ "$_m29d_e04_c" "$_m29d_e04_m"
done

check_cmd "durcissement : les exceptions du registre (exceptions.json, M26) sont lues, pas réécrites dans les tests" \
  _m29d_contient "$_M29D_P_ANSIBLE" "$_m29d_e04_dir/conftest.py" 'exceptions\.json'
_m29d_e04_ini="$(_m29d_contenu "$_M29D_P_ANSIBLE" "$_m29d_e04_dir/pytest.ini")$(_m29d_contenu "$_M29D_P_ANSIBLE" pyproject.toml)"
check_cmd "marqueurs déclarés et --strict-markers (pytest.ini ou pyproject.toml)" \
  bash -c 'grep -q -- "--strict-markers" <<<"$1" && grep -Eq "durcissement:|\"durcissement" <<<"$1"' _ "$_m29d_e04_ini"
check_cmd "pyproject.toml : pytest-testinfra 10.2 dans les dépendances du projet" \
  _m29d_contient "$_M29D_P_ANSIBLE" pyproject.toml 'pytest-testinfra[^0-9]*10\.2'
check_cmd "uv.lock : pytest-testinfra verrouillé en 10.2.x" \
  bash -c 'grep -A1 "name = \"pytest-testinfra\"" <<<"$1" | grep -Eq "version = \"10\.2\."' _ "$(_m29d_contenu "$_M29D_P_ANSIBLE" uv.lock)"
check_cmd "uv.lock : pytest-xdist (exécution parallèle -n)" \
  bash -c 'grep -q "name = \"pytest-xdist\"" <<<"$1"' _ "$(_m29d_contenu "$_M29D_P_ANSIBLE" uv.lock)"

# --- CI ----------------------------------------------------------------------------------------------
_m29d_e04_ci="$(_m29d_contenu "$_M29D_P_ANSIBLE" .gitlab-ci.yml)"
check_cmd ".gitlab-ci.yml : Testinfra lancé sur les hôtes de l'inventaire (ansible://) avec la clé de CI" \
  bash -c 'grep -q "ansible://" <<<"$1" && grep -q -- "--ssh-identity-file" <<<"$1"' _ "$_m29d_e04_ci"
check_cmd "un job Testinfra de plateforme/ansible a RÉUSSI ces 7 derniers jours" \
  _m29d_job_reussi "$_M29D_P_ANSIBLE" 'testinfra' 7
