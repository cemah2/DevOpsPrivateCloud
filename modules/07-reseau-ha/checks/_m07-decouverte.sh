# shellcheck shell=bash
# _m07-decouverte.sh — fonctions partagées par les checks M07-E02 à M07-E08 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m07d_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).

_M07D_ANSIBLE="${WB_SRC:-$HOME/src}/ansible"
_M07D_INFRA="${WB_SRC:-$HOME/src}/infra"
_M07D_DNS="10.10.20.10"

# Maquette : nom → VMID (introduction du module 07). hap01 (2079) arrive au palier 2.
declare -gA _M07D_VMID=(
  [net01]=2070 [spine01]=2071 [spine02]=2072 [leaf01]=2073 [leaf02]=2074
  [srv01]=2075 [srv02]=2076 [lyo-gw01]=2077 [lyo-pc01]=2078
)
_M07D_VMS="net01 spine01 spine02 leaf01 leaf02 srv01 srv02 lyo-gw01 lyo-pc01"
_M07D_ROUTEURS="spine01 spine02 leaf01 leaf02"

# _m07d_qm VMID — configuration Proxmox de la VM (qm config, lu en root sur pve01).
_m07d_qm() {
  remote "${WB_PVE_HOST:-pve01}" "qm config $1" 2>/dev/null || true
}

# _m07d_etiquettes CONFIG ETIQ… — la VM porte toutes les étiquettes données.
_m07d_etiquettes() {
  local conf="$1" e tags
  shift
  tags="$(sed -n 's/^tags: //p' <<<"$conf")"
  for e in "$@"; do
    grep -Eq "(^|;)$e(;|$)" <<<"$tags" || return 1
  done
}

# _m07d_dans_pool VMID — la VM est membre du pool lab.
_m07d_dans_pool() {
  remote "${WB_PVE_HOST:-pve01}" "pvesh get /pools/lab --output-format json" 2>/dev/null \
    | jq -e --argjson id "$1" '(.members // .[0].members // []) | map(select(.vmid == $id)) | length == 1' >/dev/null
}

# _m07d_carte CONFIG N VNET — la carte netN est branchée sur VNET.
_m07d_carte() {
  grep -Eq "^net$2: .*bridge=$3(,|$)" <<<"$1"
}

# _m07d_projet_fichier PROJET CHEMIN — le fichier existe sur main du projet GitLab (ex. plateforme/ansible).
_m07d_projet_fichier() {
  local p c
  p="$(jq -rn --arg v "$1" '$v | @uri')"
  c="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$p/repository/files/$c?ref=main" >/dev/null 2>&1
}

# _m07d_projet_brut PROJET CHEMIN — contenu du fichier sur main (vide si absent).
_m07d_projet_brut() {
  local p c
  p="$(jq -rn --arg v "$1" '$v | @uri')"
  c="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$p/repository/files/$c/raw?ref=main" 2>/dev/null || true
}

# _m07d_projet_dossier PROJET CHEMIN — le dossier existe sur main et n'est pas vide.
_m07d_projet_dossier() {
  local p c
  p="$(jq -rn --arg v "$1" '$v | @uri')"
  c="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$p/repository/tree?path=$c&ref=main" 2>/dev/null | jq -e 'length > 0' >/dev/null
}

# _m07d_ansible_main CHEMIN — raccourci pour plateforme/ansible.
_m07d_ansible_main() {
  _m07d_projet_fichier plateforme/ansible "$1"
}

# _m07d_vtysh HÔTE "commande" — sortie d'une commande vtysh (lecture : show …), vide si échec.
_m07d_vtysh() {
  remote "$1" "sudo -n vtysh -c '$2'" 2>/dev/null || true
}

# _m07d_actif HÔTE UNITÉ — l'unité systemd est active ET activée au démarrage.
_m07d_actif() {
  remote "$1" "systemctl is-active --quiet $2 && systemctl is-enabled --quiet $2" >/dev/null 2>&1
}

# _m07d_ping HÔTE CIBLE [ESPACE] — HÔTE (ou un espace de noms de HÔTE) joint CIBLE.
_m07d_ping() {
  if [[ -n "${3:-}" ]]; then
    remote "$1" "sudo -n ip netns exec $3 ping -c 2 -W 2 $2" >/dev/null 2>&1
  else
    remote "$1" "ping -c 2 -W 2 $2" >/dev/null 2>&1
  fi
}

# _m07d_vault_lab CHEMIN — fichier de la copie de travail Ansible chiffré sous l'identité « lab ».
_m07d_vault_lab() {
  # shellcheck disable=SC2016  # « $ANSIBLE_VAULT » est le texte littéral de l'en-tête
  head -n 1 "$_M07D_ANSIBLE/$1" 2>/dev/null | grep -q '^\$ANSIBLE_VAULT;1\.2;AES256;lab'
}
