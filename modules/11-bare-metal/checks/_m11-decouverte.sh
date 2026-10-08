# shellcheck shell=bash
# _m11-decouverte.sh — fonctions partagées par les checks M11-E02 à M11-E05 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m11d_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).

_M11D_CFG="$HOME/.config/workbook"
_M11D_PVE="${WB_PVE_HOST:-pve01}"
_M11D_PROJET_PROV="projects/plateforme%2Fprovisioning"
_M11D_PROJET_ANSIBLE="projects/plateforme%2Fansible"
_M11D_PXE_URL="http://pxe01.par1.medisphere.internal"
_M11D_RACINE_PKI="/usr/local/share/ca-certificates/medisphere-root-ca.crt"

# Dossier temporaire du check (effacé à la sortie) : known_hosts des serveurs fraîchement installés.
_M11D_TMP="$(mktemp -d)"
trap 'rm -rf "$_M11D_TMP"' EXIT

# _m11d_qm_config VMID — configuration Proxmox de la VM (texte de « qm config »), vide si absente.
_m11d_qm_config() {
  remote "$_M11D_PVE" "qm config $1" 2>/dev/null || true
}

# _m11d_qm_running VMID — la VM tourne.
_m11d_qm_running() {
  remote "$_M11D_PVE" "qm status $1" 2>/dev/null | grep -q 'status: running'
}

# _m11d_ip_vm VMID — première adresse IPv4 (hors boucle locale) vue par l'agent QEMU, vide sinon.
_m11d_ip_vm() {
  remote "$_M11D_PVE" "qm guest cmd $1 network-get-interfaces" 2>/dev/null \
    | jq -r '[.[] | select(.name != "lo") | .["ip-addresses"][]? | select(.["ip-address-type"] == "ipv4")
              | .["ip-address"]][0] // empty' 2>/dev/null || true
}

# _m11d_ssh_bm ADRESSE COMMANDE — SSH en admin vers un serveur fraîchement installé (clé de adm01).
# Sa clé d'hôte n'est pas encore signée par la CA SSH : elle est acceptée dans un known_hosts
# TEMPORAIRE, propre au check, qui ne modifie pas celui de l'apprenant.
_m11d_ssh_bm() {
  local ip="$1"; shift
  # shellcheck disable=SC2086  # WB_SSH_OPTS doit être découpé en mots
  ssh -o BatchMode=yes -o ConnectTimeout="$WB_TIMEOUT" -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile="$_M11D_TMP/known_hosts" $WB_SSH_OPTS "admin@$ip" -- "$@"
}

# _m11d_kea HÔTE — configuration CHARGÉE par kea-dhcp4 (config-get par la socket UNIX), JSON ou vide.
_m11d_kea() {
  remote "$1" 'printf "{ \"command\": \"config-get\" }" | sudo -n socat - UNIX-CONNECT:/run/kea/kea4-ctrl-socket' 2>/dev/null || true
}

# _m11d_contenu_main PROJET CHEMIN — contenu brut d'un fichier sur main (vide si absent).
_m11d_contenu_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin/raw?ref=main" 2>/dev/null || true
}

# _m11d_fichier_main PROJET CHEMIN — le fichier existe sur main.
_m11d_fichier_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin?ref=main" >/dev/null 2>&1
}

# _m11d_http CHEMIN — contenu servi par nginx sur pxe01 (lu depuis adm01, MGMT autorisé), vide sinon.
_m11d_http() {
  curl -sf --max-time "$WB_TIMEOUT" "$_M11D_PXE_URL/$1" 2>/dev/null || true
}

# _m11d_sha_pxe CHEMIN — empreinte SHA-256 d'un fichier de pxe01 (vide si absent).
_m11d_sha_pxe() {
  remote pxe01 "sha256sum $1 2>/dev/null | cut -d ' ' -f 1" 2>/dev/null || true
}

# _m11d_sha_racine_locale — empreinte de la racine de la PKI telle qu'installée sur adm01.
_m11d_sha_racine_locale() {
  sha256sum "$_M11D_RACINE_PKI" 2>/dev/null | cut -d ' ' -f 1 || true
}

# _m11d_sans_clair TEXTE — aucun mot de passe en clair (mêmes motifs que outils/verifier.sh).
_m11d_sans_clair() {
  [[ -n "$1" ]] \
    && ! grep -qE 'passwd/(root|user)-password(-again)?[[:space:]]+password[[:space:]]+[^[:space:]]' <<<"$1" \
    && ! grep -qE -- '--plaintext' <<<"$1" \
    && ! grep -qE '^[[:space:]]*rootpw[[:space:]]+[^-[:space:]]' <<<"$1" \
    && ! { grep -E '^[[:space:]]*user[[:space:]].*--password' <<<"$1" | grep -qv -- '--iscrypted'; }
}
