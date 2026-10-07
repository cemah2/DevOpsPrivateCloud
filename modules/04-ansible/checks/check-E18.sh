# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # bash -c et regex : les $ sont évalués par le sous-shell, pas ici
#
# check-E18.sh — M04-E18 : Collections : utiliser et créer medisphere.socle
# À lancer depuis adm01. Lecture seule : collections installées et suivies par Git, plugin
# documenté, tests unitaires (s'ils peuvent tourner), pare-feu rendu par le filtre (--check).

# shellcheck source=_m04-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-operationnel.sh"

title "M04-E18 — Collections : utiliser et créer medisphere.socle"
require_cmd git jq curl

_m04o_col="collections/ansible_collections/medisphere/socle"

# --- Collections externes ---------------------------------------------------------------------------
check_cmd "requirements.yml : versions exactes (aucune plage)" \
  bash -c 'f="$1/collections/requirements.yml"; grep -Eq "version:" "$f" && ! grep -Eq "version:[[:space:]]*\"?[^\"0-9=]|version:.*[<>*]" "$f"' \
  _ "$_M04_SRC"
_m04o_liste="$(_m04_ans ansible-galaxy collection list -p collections 2>/dev/null)" || true
check_output "community.proxmox 2.x installée dans ./collections" '^community\.proxmox[[:space:]]+2\.' printf '%s\n' "$_m04o_liste"
check_output "community.general 13.x installée dans ./collections" '^community\.general[[:space:]]+13\.' printf '%s\n' "$_m04o_liste"
check_output "ansible.posix 2.x installée dans ./collections" '^ansible\.posix[[:space:]]+2\.' printf '%s\n' "$_m04o_liste"
check_cmd "les collections externes ne sont pas versionnées" \
  bash -c '[ -z "$(git -C "$1" ls-files collections/ansible_collections/community collections/ansible_collections/ansible)" ]' _ "$_M04_SRC"

# --- medisphere.socle ---------------------------------------------------------------------------------
check_cmd "$_m04o_col/galaxy.yml publié sur main" _m04_fichier_main "$_m04o_col/galaxy.yml"
check_output "medisphere.socle reconnue par ansible-galaxy (avec un numéro de version)" \
  '^medisphere\.socle[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+' printf '%s\n' "$_m04o_liste"
check_cmd "meta/runtime.yml déclare les versions d'ansible-core supportées" \
  _m04_contient "$_m04o_col/meta/runtime.yml" '^requires_ansible:'
check_cmd "le filtre medisphere.socle.regle_nft est documenté (ansible-doc)" \
  _m04_ans ansible-doc -t filter medisphere.socle.regle_nft
check_cmd "le rôle pare_feu utilise le filtre (plus de macro Jinja)" \
  bash -c 'f="$1/roles/pare_feu/templates/nftables.conf.j2"; grep -q "medisphere.socle.regle_nft" "$f" && ! grep -q "{%-\? *macro" "$f"' \
  _ "$_M04_SRC"
check_cmd "la collection contient au moins un rôle partagé, utilisé par un rôle du projet" \
  bash -c 'for r in "$1/$2"/roles/*/; do n="$(basename "$r")"; grep -rq "medisphere.socle.$n" "$1/roles" && exit 0; done; exit 1' \
  _ "$_M04_SRC" "$_m04o_col"
check_cmd "des tests unitaires du filtre existent" \
  bash -c 'ls "$1/$2"/tests/unit/plugins/filter/test_*.py >/dev/null 2>&1' _ "$_M04_SRC" "$_m04o_col"
if [[ -x "$_M04_SRC/.venv/bin/pytest" ]]; then
  check_cmd "les tests unitaires de la collection passent" \
    _m04_ans env PYTHONPATH=collections pytest -q "$_m04o_col/tests/unit"
else
  skip "tests unitaires de la collection" "pytest absent de l'environnement du projet"
fi

# --- Même pare-feu qu'avant le remaniement ------------------------------------------------------------
_m04o_sortie="$(_m04_simuler playbooks/gw01-pare-feu.yml)"
check_cmd "--check du pare-feu après remaniement : fichier identique sur gw01" _m04_recap "$_m04o_sortie" gw01
