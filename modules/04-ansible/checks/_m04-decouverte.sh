# shellcheck shell=bash
# _m04-decouverte.sh — fonctions partagées par les checks M04-E02 à M04-E08 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande
# qui peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Ansible est lancé depuis la copie de travail ~/src/ansible, avec l'environnement du projet
# (.venv, jamais resynchronisé) et SA configuration (ansible.cfg du projet, ANSIBLE_CONFIG
# ignoré). Les playbooks ne sont lancés qu'en mode --check : rien n'est modifié sur le lab.

_M04_PROJET="projects/plateforme%2Fansible"
_M04_SRC="${WB_SRC:-$HOME/src}/ansible"
_M04_SOCLE="gw01 adm01 dns01 git01 runner01"

# Dès M04-E13, l'inventaire par défaut du projet est l'inventaire dynamique Proxmox : les
# commandes Ansible des checks ont alors besoin des mêmes variables que l'apprenant
# (PROXMOX_*, REQUESTS_CA_BUNDLE). Chargées ici si le fichier existe (inoffensif avant E13).
_M04_ENV_PVE="$HOME/.config/workbook/pve-ansible.env"
if [[ -r "$_M04_ENV_PVE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$_M04_ENV_PVE"
  set +a
fi

# _m04_role_base_en_place — vrai une fois M04-E10 fait : le rôle base a repris (et remplacé)
# les playbooks du palier 1. Les checks E05 à E08 sautent alors leurs contrôles de playbook
# (fichiers supprimés, variables trousse_* renommées base_*) et ne gardent que l'état des hôtes.
_m04_role_base_en_place() {
  [[ -s "$_M04_SRC/roles/base/tasks/main.yml" && ! -e "$_M04_SRC/playbooks/trousse-diagnostic.yml" ]]
}

# _m04_ans COMMANDE [ARGS…] — exécute un outil de l'environnement du projet, depuis sa racine.
_m04_ans() {
  (
    cd "$_M04_SRC" 2>/dev/null || exit 1
    env -u ANSIBLE_CONFIG PATH="$_M04_SRC/.venv/bin:$PATH" \
      ANSIBLE_NOCOLOR=1 ANSIBLE_FORCE_COLOR=0 "$@"
  )
}

# _m04_fichier_main CHEMIN — le fichier existe sur la branche main du projet (API GitLab).
_m04_fichier_main() {
  local chemin
  chemin="$(jq -rn --arg v "$1" '$v | @uri')"
  gitlab_api "$_M04_PROJET/repository/files/$chemin?ref=main" >/dev/null 2>&1
}

# _m04_contient FICHIER REGEX — le fichier (relatif au projet) correspond à la regex étendue.
_m04_contient() { grep -Eq -- "$2" "$_M04_SRC/$1" 2>/dev/null; }

# _m04_json COMMANDE [ARGS…] — lance « ansible » ou « ansible-playbook » de l'environnement du
#   projet avec le callback JSON (collection ansible.posix, installée en E02) : un seul
#   document JSON sur la sortie standard, même si des hôtes échouent. Vide si Ansible n'a
#   rien pu produire (erreur de syntaxe, inventaire illisible…). Le format « une ligne »
#   (-o, callback oneline) est déprécié depuis ansible-core 2.19 : on ne s'en sert pas.
_m04_json() {
  _m04_ans env ANSIBLE_LOAD_CALLBACK_PLUGINS=1 ANSIBLE_STDOUT_CALLBACK=ansible.posix.json \
    "$@" 2>/dev/null || true
}

# _m04_resultat JSON HÔTE FILTRE — applique un filtre jq au résultat de la première tâche
#   pour l'hôte (commande ad hoc lancée par _m04_json).
_m04_resultat() {
  jq -r --arg h "$2" ".plays[0].tasks[0].hosts[\$h] // {} | $3" <<<"$1" 2>/dev/null || true
}

# _m04_simuler PLAYBOOK [OPTIONS…] — lance le playbook en --check (sortie JSON, voir _m04_json).
#   Usage : sortie="$(_m04_simuler playbooks/x.yml)"
_m04_simuler() {
  local pb="$1"
  shift
  _m04_json ansible-playbook "$pb" --check "$@"
}

# _m04_recap SORTIE HÔTE — d'après les statistiques finales, l'hôte a été traité sans
#   changement, sans échec et sans être injoignable.
_m04_recap() {
  jq -e --arg h "$2" '.stats[$h] as $s | $s != null and $s.changed == 0
    and $s.failures == 0 and $s.unreachable == 0' <<<"$1" >/dev/null 2>&1
}

# _m04_debug HÔTE EXPRESSION — valeur d'une expression Jinja vue par l'hôte (module debug,
#   exécuté sur adm01 sans connexion à l'hôte), en JSON compact (chaîne entre guillemets,
#   liste…) ; vide si erreur.
_m04_debug() {
  local sortie
  sortie="$(_m04_json ansible "$1" -m ansible.builtin.debug -a "msg={{ $2 }}")"
  jq -c --arg h "$1" '.plays[0].tasks[0].hosts[$h] | select(.failed != true) | .msg' \
    <<<"$sortie" 2>/dev/null || true
}

# _m04_paquet HÔTE PAQUET — le paquet Debian est installé sur l'hôte.
_m04_paquet() {
  remote "$1" "dpkg-query -W -f='\${Status}' $2 2>/dev/null | grep -q 'install ok installed'"
}
