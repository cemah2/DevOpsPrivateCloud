# shellcheck shell=bash
# _m05-decouverte.sh — fonctions partagées par les checks M05-E02 à M05-E08 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande
# qui peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Sources lues :
#   - Proxmox, en root sur pve01 (alias WB_PVE_HOST) : qm config, qm cloudinit dump,
#     qm guest cmd/exec (agent QEMU), pvesh, pveum. JAMAIS avec le jeton de l'apprenant :
#     un check doit pouvoir diagnostiquer un jeton en panne ;
#   - la copie de travail ~/src/infra et l'état LOCAL de envs/lab-m05 (terraform.tfstate,
#     lu par jq, jamais modifié) ;
#   - OpenTofu lui-même, lancé depuis envs/lab-m05 avec les accès de l'apprenant
#     (~/.config/workbook/pve-tofu.env) et uniquement en lecture : validate, fmt -check,
#     show -json -config, plan -lock=false sans -out (rien n'est enregistré ni appliqué) ;
#   - la forge (API GitLab, jeton des checks).
#
# Quand envs/lab-m05 utilise un backend distant (M05-E11 et suivants), les contrôles qui
# lisent l'état local ou lancent un plan sont ignorés : lab/bin/check 05 11 prend le relais.

_M05_PROJET="projects/plateforme%2Finfra"
_M05_SRC="${WB_SRC:-$HOME/src}/infra"
_M05_ENV="$_M05_SRC/envs/lab-m05"
_M05_ACCES="$HOME/.config/workbook/pve-tofu.env"
_M05_STOCKAGE="${WB_STORAGE_NVME:-local-nvme}"

# _m05_fichier_main CHEMIN — le fichier existe sur la branche main de plateforme/infra.
_m05_fichier_main() {
  local chemin
  chemin="$(jq -rn --arg v "$1" '$v | @uri')"
  gitlab_api "$_M05_PROJET/repository/files/$chemin?ref=main" >/dev/null 2>&1
}

# _m05_brut_main CHEMIN — contenu brut du fichier sur main (vide si absent).
_m05_brut_main() {
  local chemin
  chemin="$(jq -rn --arg v "$1" '$v | @uri')"
  gitlab_api "$_M05_PROJET/repository/files/$chemin/raw?ref=main" 2>/dev/null || true
}

# _m05_tf_main — contenu concaténé de tous les fichiers .tf et .tfvars de envs/lab-m05 sur main
#   (le découpage en fichiers est libre : on cherche dans l'ensemble).
_m05_tf_main() {
  local arbre f
  arbre="$(gitlab_api "$_M05_PROJET/repository/tree?ref=main&path=envs%2Flab-m05&per_page=100" 2>/dev/null)" || return 0
  for f in $(jq -r '.[] | select(.type == "blob") | .path | select(test("\\.(tf|tfvars)$"))' <<<"$arbre" 2>/dev/null); do
    _m05_brut_main "$f"
    printf '\n'
  done
}

# _m05_val JSON FILTRE — valeur brute d'un champ JSON (vide si absent ou JSON invalide).
_m05_val() { jq -r "$2" <<<"$1" 2>/dev/null || true; }

# _m05_pve COMMANDE — commande en root sur pve01 (sortie standard), jamais d'échec.
_m05_pve() { remote "$WB_PVE_HOST" "$1" 2>/dev/null || true; }

# _m05_qm_config VMID — configuration courante de la VM (vide si elle n'existe pas).
_m05_qm_config() { _m05_pve "qm config $1 --current 2>/dev/null"; }

# _m05_cle CONFIG CLÉ — valeur d'une ligne « clé: valeur » d'une sortie de qm config.
_m05_cle() { sed -n "s/^$2: //p" <<<"$1" | head -n 1; }

# _m05_ressource VMID — l'entrée JSON de la VM dans /cluster/resources (pool, tags, status…).
_m05_ressource() {
  local tout
  tout="$(_m05_pve "pvesh get /cluster/resources --type vm --output-format json")"
  jq -c --argjson id "$1" '[.[] | select(.vmid == $id)][0] // empty' <<<"$tout" 2>/dev/null || true
}

# _m05_etiquettes VMID — étiquettes Proxmox de la VM, une par ligne, triées.
_m05_etiquettes() {
  _m05_cle "$(_m05_qm_config "$1")" tags | tr -s ';, ' '\n' | sed '/^$/d' | sort
}

# _m05_etiquettes_saines VMID — porte env-m05 et aucune étiquette réservée (socle, role-*,
#   gold, current, base) : c'est ce qu'un clone sans étiquettes déclarées n'a PAS.
_m05_etiquettes_saines() {
  local e
  e="$(_m05_etiquettes "$1")"
  grep -qx 'env-m05' <<<"$e" && ! grep -Eqx 'socle|role-.*|gold|current|base' <<<"$e"
}

# _m05_ipv4_agent VMID — première IPv4 non locale rapportée par l'agent QEMU (vide sinon).
_m05_ipv4_agent() {
  local j
  j="$(_m05_pve "qm guest cmd $1 network-get-interfaces 2>/dev/null")"
  jq -r '[.[]? | ."ip-addresses"[]? | select(."ip-address-type" == "ipv4")
         | ."ip-address" | select(startswith("127.") | not)][0] // empty' <<<"$j" 2>/dev/null || true
}

# _m05_guest_sortie VMID COMMANDE… — sortie standard d'une commande exécutée par l'agent.
_m05_guest_sortie() {
  local id="$1" j
  shift
  j="$(_m05_pve "qm guest exec $id --timeout 20 -- $*")"
  jq -r '."out-data" // empty' <<<"$j" 2>/dev/null || true
}

# _m05_backend_distant — vrai si envs/lab-m05 déclare un backend (s3…) : état migré (E11).
_m05_backend_distant() {
  grep -Eqs '^[[:space:]]*backend[[:space:]]+"' "$_M05_ENV"/*.tf "$_M05_ENV"/*.tofu 2>/dev/null
}

# _m05_etat FILTRE — applique un filtre jq à l'état local (vide si absent ou illisible).
_m05_etat() { jq -r "$1" "$_M05_ENV/terraform.tfstate" 2>/dev/null || true; }

# _m05_tofu ARGUMENTS… — tofu lancé depuis envs/lab-m05, accès de l'apprenant chargés,
#   sans couleur ni question, sans variables TF_CLI_ARGS* héritées. Délai maximal : 10 min.
_m05_tofu() {
  (
    cd "$_M05_ENV" 2>/dev/null || exit 1
    if [[ -r "$_M05_ACCES" ]]; then
      set -a
      # shellcheck source=/dev/null
      . "$_M05_ACCES"
      set +a
    fi
    env -u TF_CLI_ARGS -u TF_CLI_ARGS_plan -u TF_WORKSPACE TF_IN_AUTOMATION=1 TF_INPUT=0 \
      timeout 600 tofu "$@"
  )
}

# _m05_plan_vide — tofu plan sans verrou ni enregistrement : code retour 0 = aucun changement
#   (-detailed-exitcode : 0 rien à faire, 1 erreur, 2 changements).
_m05_plan_vide() { _m05_tofu plan -lock=false -input=false -no-color -detailed-exitcode >/dev/null 2>&1; }

# _m05_config_json — configuration de envs/lab-m05 en JSON (tofu show -json -config).
_m05_config_json() { _m05_tofu show -json -config 2>/dev/null || true; }

# _m05_tf_contient REGEX — un fichier .tf de envs/lab-m05 correspond à la regex étendue.
_m05_tf_contient() { grep -Eqs -- "$1" "$_M05_ENV"/*.tf; }

# _m05_controles_etat_et_plan TITRE — contrôles communs de fin d'exercice : l'état local
#   connaît la ressource demandée (filtre jq qui doit renvoyer « true »), et le plan est vide.
#   Usage : _m05_controles_etat_et_plan "description" 'FILTRE_JQ'
_m05_controles_etat_et_plan() {
  if _m05_backend_distant; then
    skip "$1 (état local)" "état de envs/lab-m05 sur un backend distant : voir lab/bin/check 05 11"
    skip "tofu plan dans envs/lab-m05 : aucun changement" "état distant : voir lab/bin/check 05 11"
    return 0
  fi
  check_output "$1" '^true$' _m05_etat "$2"
  check_cmd "tofu plan dans envs/lab-m05 : aucun changement (le code décrit la réalité)" _m05_plan_vide
}
