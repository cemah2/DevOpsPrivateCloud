# shellcheck shell=bash
# _m06-production.sh — fonctions partagées par les checks M06-E24 à M06-E34 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Variables de lab/lab.env utilisées : WB_PVE_HOST, WB_PBS_HOST, WB_GITLAB_URL,
# WB_GITLAB_TOKEN_FILE, WB_NETBOX_URL, WB_NETBOX_TOKEN_FILE.
# Fichier de l'apprenant lu (sans être modifié) : ~/.config/workbook/kea-supervision.env (M06-E25).

_M06P_RACINE=/usr/local/share/ca-certificates/medisphere-root-ca.crt
_M06P_ZONES=(par1.medisphere.internal par2.medisphere.internal 10.10.in-addr.arpa 20.10.in-addr.arpa)
_M06P_KEA_ENV="$HOME/.config/workbook/kea-supervision.env"

# --- Proxmox (root sur pve01) --------------------------------------------------------------

_M06P_VMS_CACHE=""
# _m06p_vms — JSON de /cluster/resources (VMs), en cache. Échoue si pve01 ne répond pas.
_m06p_vms() {
  if [[ -z "$_M06P_VMS_CACHE" ]]; then
    _M06P_VMS_CACHE="$(remote "$WB_PVE_HOST" "pvesh get /cluster/resources --type vm --output-format json" 2>/dev/null)" \
      || _M06P_VMS_CACHE="indisponible"
    jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$_M06P_VMS_CACHE" || _M06P_VMS_CACHE="indisponible"
  fi
  [[ "$_M06P_VMS_CACHE" != "indisponible" ]] || return 1
  printf '%s\n' "$_M06P_VMS_CACHE"
}
# _m06p_charger — remplit le cache dans le shell courant (à appeler en tête de chaque check).
_m06p_charger() { _m06p_vms >/dev/null || true; }

# _m06p_vm_jq VMID FILTRE_JQ — applique un filtre booléen à la VM (échoue si absente).
_m06p_vm_jq() {
  local v
  v="$(_m06p_vms)" || return 1
  jq -e --argjson id "$1" "[.[] | select(.vmid == \$id)] | length == 1 and (.[0] | $2)" >/dev/null <<<"$v"
}

# _m06p_vm_etiquettes VMID ETIQUETTE... — la VM porte toutes ces étiquettes Proxmox.
_m06p_vm_etiquettes() {
  local id="$1" e
  shift
  for e in "$@"; do
    _m06p_vm_jq "$id" "((.tags // \"\") | split(\";\") | index(\"$e\")) != null" || return 1
  done
}

# _m06p_clone_complet VMID — aucun disque de la VM ne dépend d'un template (pas de « base-NNNN- »).
_m06p_clone_complet() {
  remote "$WB_PVE_HOST" "qm config $1" 2>/dev/null \
    | awk '/^(scsi|virtio|sata|ide)[0-9]+:/ && !/media=cdrom/ && !/cloudinit/' \
    | { ! grep -q 'base-[0-9]*-disk'; }
}

# _m06p_vm_a_existe VMID — une tâche de création (clone, restauration) a eu lieu pour ce VMID.
_m06p_vm_a_existe() {
  remote "$WB_PVE_HOST" "pvesh get /nodes/\$(hostname)/tasks --vmid $1 --source all --limit 1000 --output-format json" 2>/dev/null \
    | grep -Eq '"type" *: *"(qmclone|qmcreate|qmrestore)"'
}

# _m06p_vm_absente VMID — la VM n'existe plus (échoue si pve01 ne répond pas).
_m06p_vm_absente() {
  remote "$WB_PVE_HOST" "true" >/dev/null 2>&1 || return 1
  ! remote "$WB_PVE_HOST" "qm status $1" >/dev/null 2>&1
}

# --- DNS -------------------------------------------------------------------------------------

# _m06p_serie SERVEUR ZONE — numéro de série du SOA servi par le serveur faisant autorité (5300).
_m06p_serie() {
  dig +short +norecurse +time=3 +tries=2 "@$1" -p 5300 "$2" SOA 2>/dev/null | awk 'NR == 1 {print $3}'
}

# _m06p_series_egales ZONE — même numéro de série, non vide, sur dns01 et dns02.
_m06p_series_egales() {
  local a b
  a="$(_m06p_serie 10.10.20.10 "$1")"
  b="$(_m06p_serie 10.10.20.16 "$1")"
  [[ -n "$a" && "$a" == "$b" ]]
}

# _m06p_ad SERVEUR NOM [TYPE] — réponse validée DNSSEC (drapeau ad) par le récurseur.
_m06p_ad() {
  dig +dnssec +time=3 +tries=2 "@$1" "$2" "${3:-A}" 2>/dev/null | grep -Eq 'flags:[a-z ]* ad[ ;]'
}

# --- Kea (socket de contrôle HTTPS, compte de supervision de l'apprenant) ----------------------

# _m06p_kea SERVEUR COMMANDE — réponse JSON (premier élément). Identifiants lus dans un
# sous-shell, passés à curl par stdin (jamais dans « ps »).
_m06p_kea() {
  [[ -r "$_M06P_KEA_ENV" ]] || return 1
  (
    set +u
    # shellcheck source=/dev/null
    source "$_M06P_KEA_ENV" >/dev/null 2>&1 || exit 1
    [[ -n "${KEA_API_USER:-}" && -n "${KEA_API_PASSWORD:-}" ]] || exit 1
    curl -sS --fail --max-time "$WB_TIMEOUT" --cacert "$_M06P_RACINE" -K - -H 'Content-Type: application/json' \
      --data "{\"command\": \"$2\"}" "https://$1:8004/" <<<"user = \"${KEA_API_USER}:${KEA_API_PASSWORD}\""
  ) 2>/dev/null | jq -e '.[0]'
}

# _m06p_kea_ha SERVEUR FILTRE_JQ — filtre booléen sur .arguments["high-availability"][0]["ha-servers"].
_m06p_kea_ha() {
  _m06p_kea "$1" status-get | jq -e ".arguments[\"high-availability\"][0][\"ha-servers\"] | $2" >/dev/null
}

# --- Certificats -------------------------------------------------------------------------------

# _m06p_cert_valide NOM PORT JOURS — chaîne vers la racine MédiSphère, nom correct, et expiration
# dans plus de JOURS jours.
_m06p_cert_valide() {
  local pem
  pem="$(openssl s_client -connect "$1:$2" -servername "$1" -CAfile "$_M06P_RACINE" -verify_hostname "$1" \
    -verify_return_error </dev/null 2>/dev/null | openssl x509 2>/dev/null)" || return 1
  [[ -n "$pem" ]] && openssl x509 -noout -checkend $(($3 * 86400)) <<<"$pem" >/dev/null
}

# --- GitLab (jeton des checks, lecture) --------------------------------------------------------

# _m06p_fichier_main PROJET CHEMIN — contenu d'un fichier de la branche main.
_m06p_fichier_main() {
  local p="${1//\//%2F}" f="${2//\//%2F}"
  gitlab_api "projects/$p/repository/files/$f/raw?ref=main"
}

# _m06p_fichier_existe PROJET CHEMIN — le fichier existe sur main (et n'est pas vide).
_m06p_fichier_existe() {
  local c
  c="$(_m06p_fichier_main "$1" "$2" 2>/dev/null)" || return 1
  [[ -n "$c" ]]
}

# _m06p_runbook PREFIXE — un runbook « PREFIXE* » existe dans docs/socle/runbooks/ de plateforme/medisphere.
_m06p_runbook() {
  gitlab_api "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=docs%2Fsocle%2Frunbooks&per_page=100" 2>/dev/null \
    | jq -e --arg p "$1" 'any(.[]?; .name | startswith($p))' >/dev/null
}

# _m06p_job_reussi PROJET MOTIF — un job de main dont le nom contient MOTIF a réussi (100 derniers).
_m06p_job_reussi() {
  local p="${1//\//%2F}"
  gitlab_api "projects/$p/jobs?scope%5B%5D=success&per_page=100" 2>/dev/null \
    | jq -e --arg m "$2" 'any(.[]?; .ref == "main" and (.name | contains($m)))' >/dev/null
}

# --- Divers ------------------------------------------------------------------------------------

# _m06p_port_ferme HÔTE_SSH DESTINATION PORT — depuis l'hôte, connexion TCP impossible (refus OU
# filtrage). Échoue si l'hôte source lui-même ne répond pas (sinon : faux positif).
_m06p_port_ferme() {
  remote "$1" true >/dev/null 2>&1 || return 1
  remote "$1" "! timeout 4 bash -c 'exec 3<>/dev/tcp/$2/$3' 2>/dev/null"
}

# _m06p_port_ouvert HÔTE_SSH DESTINATION PORT — depuis l'hôte, connexion TCP possible.
_m06p_port_ouvert() {
  remote "$1" "timeout 4 bash -c 'exec 3<>/dev/tcp/$2/$3'" >/dev/null 2>&1
}
