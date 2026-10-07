# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# _m04-operationnel.sh — fonctions partagées par les checks M04-E10 à M04-E23 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Complète _m04-decouverte.sh (chargé ici : _m04_ans, _m04_simuler, _m04_recap, _m04_debug…).
# Préfixe _m04o_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check).

# shellcheck source=_m04-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-decouverte.sh"

# Inventaire dynamique (M04-E13) : les commandes Ansible des checks ont besoin des mêmes
# variables que l'apprenant (PROXMOX_*, REQUESTS_CA_BUNDLE). Elles restent dans ce processus.
_M04O_ENV_PVE="$HOME/.config/workbook/pve-ansible.env"
if [[ -r "$_M04O_ENV_PVE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$_M04O_ENV_PVE"
  set +a
fi

_M04O_VAULT="inventories/lab/group_vars/all/vault.yml"
_M04O_PASS="$HOME/.config/workbook/ansible-vault.pass"
# Hôtes joints en SSH par leurs alias (adm01 : exécution locale, voir remote()).
_M04O_DISTANTS="gw01 dns01 git01 runner01"

# _m04o_role_complet RÔLE — le rôle a la structure attendue (tâches, valeurs par défaut,
# métadonnées) dans la copie de travail.
_m04o_role_complet() {
  local r="$_M04_SRC/roles/$1"
  [[ -s "$r/tasks/main.yml" && -s "$r/defaults/main.yml" && -s "$r/meta/main.yml" ]]
}

# _m04o_vault_contient REGEX — le fichier Vault se déchiffre avec la configuration du projet
# et son contenu en clair correspond à la regex (le contenu n'est jamais affiché).
_m04o_vault_contient() {
  local clair
  clair="$(_m04_ans ansible-vault view "$_M04O_VAULT" </dev/null 2>/dev/null)" || return 1
  grep -Eq -- "$1" <<<"$clair"
}

# _m04o_vault_chiffre_partout — toutes les versions commitées de vault.yml (historique de la
# copie de travail) commencent par l'en-tête Vault : aucun secret n'a jamais été commité en clair.
_m04o_vault_chiffre_partout() {
  local c n=0
  while read -r c; do
    [[ -n "$c" ]] || continue
    n=$((n + 1))
    # shellcheck disable=SC2016  # « $ANSIBLE_VAULT » est le texte littéral de l'en-tête
    git -C "$_M04_SRC" show "$c:$_M04O_VAULT" 2>/dev/null | head -n 1 | grep -q '^\$ANSIBLE_VAULT;' || return 1
  done < <(git -C "$_M04_SRC" log --all --format=%H --diff-filter=AM -- "$_M04O_VAULT" 2>/dev/null)
  ((n > 0))
}

# _m04o_inventaire — inventaire complet en JSON (ansible-inventory --list), vide si erreur.
_m04o_inventaire() {
  _m04_ans ansible-inventory --list 2>/dev/null || true
}

# _m04o_groupe_contient JSON GROUPE HÔTE — l'hôte est membre (direct) du groupe.
_m04o_groupe_contient() {
  jq -e --arg g "$2" --arg h "$3" '(.[$g].hosts // []) | index($h) != null' <<<"$1" >/dev/null 2>&1
}

# _m04o_hostvar JSON HÔTE VARIABLE — valeur d'une variable d'hôte de l'inventaire (texte brut).
_m04o_hostvar() {
  jq -r --arg h "$2" --arg v "$3" '._meta.hostvars[$h][$v] // empty' <<<"$1" 2>/dev/null || true
}

# _m04o_echoue_avec REGEX COMMANDE [ARGS…] — la commande (outil du projet, voir _m04_ans)
# ÉCHOUE et sa sortie correspond à la regex : sert à prouver qu'un garde-fou refuse bien.
_m04o_echoue_avec() {
  local regex="$1" sortie
  shift
  if sortie="$(_m04_ans "$@" </dev/null 2>&1)"; then
    return 1
  fi
  grep -Eq -- "$regex" <<<"$sortie"
}

# _m04o_dernier_job_main NOM — statut du dernier job NOM du dernier pipeline de main.
_m04o_dernier_job_main() {
  local pid
  pid="$(gitlab_api "$_M04_PROJET/pipelines?ref=main&per_page=1" 2>/dev/null | jq -r '.[0].id // empty')" || return 0
  [[ -n "$pid" ]] || return 0
  gitlab_api "$_M04_PROJET/pipelines/$pid/jobs?per_page=100" 2>/dev/null \
    | jq -r --arg n "$1" '[.[] | select(.name == $n)][0].status // empty' 2>/dev/null || true
}

# _m04o_absent_main CHEMIN — le fichier n'existe PAS (ou plus) sur la branche main du projet.
#   L'API doit d'abord répondre pour un fichier connu (ansible.cfg) : une forge injoignable
#   ne doit pas passer pour « fichier absent ».
_m04o_absent_main() { _m04_fichier_main ansible.cfg && ! _m04_fichier_main "$1"; }

# _m04o_runner_en_ligne DESCRIPTION — un seul runner de cette description, en ligne (API admin).
_m04o_runner_en_ligne() {
  gitlab_api "runners/all?per_page=100" 2>/dev/null \
    | jq -e --arg d "$1" 'map(select(.description == $d and .status == "online")) | length == 1' >/dev/null 2>&1
}
