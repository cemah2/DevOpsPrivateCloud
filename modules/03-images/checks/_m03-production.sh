# shellcheck shell=bash
# _m03-production.sh — fonctions partagées par les checks M03-E13 à M03-E25 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande
# qui peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Tout passe par pve01 en root (pvesh, qm) : la lecture de l'état des VMs et des templates
# ne dépend ainsi d'aucun jeton de l'apprenant (ceux-ci peuvent justement être en panne).

_M03_PROJET="projects/plateforme%2Fimages"
_M03_SRC="${WB_SRC:-$HOME/src}/images"
_M03_DOC="${WB_DEPOT:-$HOME/medisphere}/docs/socle"

# _m03_vms — JSON de /cluster/resources (VMs et templates), mis en cache pour le check.
_M03_VMS_CACHE=""
_m03_vms() {
  if [[ -z "$_M03_VMS_CACHE" ]]; then
    _M03_VMS_CACHE="$(remote "$WB_PVE_HOST" "pvesh get /cluster/resources --type vm --output-format json" 2>/dev/null)" \
      || _M03_VMS_CACHE="[]"
  fi
  printf '%s\n' "$_M03_VMS_CACHE"
}

# _m03_charger — remplit le cache dans le shell courant (à appeler en tête de chaque check :
#   les appels faits dans un tube ou une substitution ne le conserveraient pas).
_m03_charger() { _m03_vms >/dev/null; }

# _m03_gold FAMILLE — templates dorés d'une famille (debian13|rocky10), triés par nom, en JSON.
_m03_gold() {
  _m03_vms | jq -c --arg f "$1" '[.[] | select((.template // 0) == 1)
    | select(((.tags // "") | split(";")) as $t | ($t | index("gold")) and ($t | index($f)))]
    | sort_by(.name)'
}

# _m03_current FAMILLE — VMID du template gold + FAMILLE + current (vide si aucun ou plusieurs).
_m03_current() {
  _m03_gold "$1" | jq -r '[.[] | select((.tags // "") | split(";") | index("current"))]
    | if length == 1 then .[0].vmid else empty end'
}

# _m03_existe VMID — la VM ou le template existe sur pve01.
_m03_existe() { _m03_vms | jq -e --argjson v "$1" 'any(.[]; .vmid == $v)' >/dev/null; }

# _m03_en_marche VMID — la VM existe et tourne.
_m03_en_marche() { _m03_vms | jq -e --argjson v "$1" 'any(.[]; .vmid == $v and .status == "running")' >/dev/null; }

# _m03_aucune_vm DEBUT FIN — aucune VM ni aucun template dans la plage de VMID.
_m03_aucune_vm() {
  _m03_vms | jq -e --argjson a "$1" --argjson b "$2" 'all(.[]; .vmid < $a or .vmid > $b)' >/dev/null
}

# _m03_gexec VMID 'commande' — exécute la commande dans la VM par l'agent QEMU (via pve01),
#   affiche sa sortie standard, renvoie son code (1 si l'agent ne répond pas).
_m03_gexec() {
  local vmid="$1" cmd="$2" j
  j="$(remote "$WB_PVE_HOST" "qm guest exec $vmid --timeout 60 -- bash -c $(printf '%q' "$cmd")" 2>/dev/null)" || return 1
  jq -r '."out-data" // ""' <<<"$j"
  jq -e '(.exited // 0) == 1 and (.exitcode // 1) == 0' >/dev/null <<<"$j"
}

# _m03_gexec_match VMID 'commande' 'regex' — la sortie de la commande correspond à la regex.
_m03_gexec_match() {
  local out
  out="$(_m03_gexec "$1" "$2")" || true
  grep -Eq -- "$3" <<<"$out"
}

# _m03_conf VMID — configuration Proxmox (qm config) de la VM.
_m03_conf() { remote "$WB_PVE_HOST" "qm config $1" 2>/dev/null; }

# _m03_api_ok "chemin" 'filtre jq' — 0 si la réponse GitLab (jeton des checks) satisfait le filtre.
_m03_api_ok() {
  local r
  r="$(gitlab_api "$1" 2>/dev/null)" || return 1
  jq -e "$2" >/dev/null 2>&1 <<<"$r"
}

# _m03_fichier_main CHEMIN — le fichier existe sur la branche main de plateforme/images.
_m03_fichier_main() {
  local p
  p="$(jq -rn --arg p "$1" '$p | @uri')"
  gitlab_api "$_M03_PROJET/repository/files/$p?ref=main" >/dev/null 2>&1
}

# _m03_fichier_main_contient CHEMIN 'regex' — le contenu du fichier sur main correspond à la regex.
_m03_fichier_main_contient() {
  local p
  p="$(jq -rn --arg p "$1" '$p | @uri')"
  gitlab_api "$_M03_PROJET/repository/files/$p/raw?ref=main" 2>/dev/null | grep -Eq -- "$2"
}

# _m03_doc_contient FICHIER 'regex'... — le document de ~/medisphere contient chaque motif (grep -Ei).
_m03_doc_contient() {
  local f="$1" m; shift
  [[ -s "$f" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" "$f" || return 1; done
}

# _m03_pas_de_panne — aucune panne M03 marquée active sur adm01.
_m03_pas_de_panne() {
  ! ls "${XDG_STATE_HOME:-$HOME/.local/state}"/workbook/pannes-actives/M03-* >/dev/null 2>&1
}
