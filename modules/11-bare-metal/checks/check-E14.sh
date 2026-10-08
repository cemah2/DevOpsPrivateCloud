# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
# check-E14.sh — M11-E14 « Provisionner un nœud Proxmox VE par le réseau » (à lancer après le
# nettoyage) : fichier de réponse dans le code (kebab-case, sans mot de passe en clair), service de
# réponse qui refuse sans jeton, gabarit iPXE, plus d'initrd PVE sur pxe01, documentation, bm04
# revenue à son état de départ. Lecture seule (le POST envoyé sans jeton ne modifie rien).

# shellcheck source=_m11-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-production.sh"

title "M11-E14 — Nœud Proxmox VE par le réseau"
require_cmd curl jq ssh

_m11_e14_rep="$(_m11p_gitlab_brut plateforme/provisioning pve-answer/bm04.toml)" || true
check_cmd "pve-answer/bm04.toml sur main de plateforme/provisioning" test -n "$_m11_e14_rep"
check_cmd "fichier de réponse : sections [global], [network], [disk-setup]" \
  bash -c '[ "$(grep -cE "^\[(global|network|disk-setup)\]" <<<"$1")" -eq 3 ]' _ "$_m11_e14_rep"
check_cmd "fichier de réponse : empreinte du mot de passe root (root-password-hashed), aucun root-password en clair" \
  bash -c 'grep -Eq "^[[:space:]]*root-password-hashed[[:space:]]*=" <<<"$1" && ! grep -Eq "^[[:space:]]*root-password[[:space:]]*=" <<<"$1"' _ "$_m11_e14_rep"
check_cmd "fichier de réponse : clés en kebab-case (aucune clé en snake_case)" \
  bash -c '! grep -Eq "^[[:space:]]*[a-z]+_[a-z_]+[[:space:]]*=" <<<"$1"' _ "$_m11_e14_rep"
check_cmd "fichier de réponse : clé SSH pour root" \
  bash -c 'grep -Eq "^[[:space:]]*root-ssh-keys[[:space:]]*=" <<<"$1"' _ "$_m11_e14_rep"

# Service de réponse : un POST sans jeton (et avec un jeton bidon) est refusé.
_m11_e14_refus() {
  local c1 c2
  c1="$(_m11p_https_code /pve/reponse -X POST -H 'Content-Type: application/json' -d '{}')"
  c2="$(_m11p_https_code /pve/reponse -X POST -H 'Authorization: Bearer essai:jeton-invalide-du-controle' \
    -H 'Content-Type: application/json' -d '{"mac":"02:00:00:00:00:01"}')"
  [[ "$c1" =~ ^(401|403)$ && "$c2" =~ ^(401|403)$ ]]
}
check_cmd "service de réponse PVE (https://pxe01…/pve/reponse) : POST sans jeton valide refusé (401/403)" _m11_e14_refus

check_output "gabarit iPXE de l'installation PVE dans gabarits/" 'pve' _m11p_gitlab_ls plateforme/provisioning gabarits
_m11_e14_racine="$(_m11p_racine_nginx)" || true
check_ssh "pxe01 : plus aucun initrd de l'installateur PVE servi (il contient le jeton)" pxe01 \
  "r='${_m11_e14_racine:-/srv/http}'; [ -d \"\$r\" ] && [ -z \"\$(sudo -n find \"\$r\" -path '*pve*' -name 'initrd*' 2>/dev/null)\" ]"
check_cmd "docs/provisioning/pve-pxe.md sur main de plateforme/medisphere" \
  _m11p_gitlab_fichier plateforme/medisphere docs/provisioning/pve-pxe.md
check_ssh "bm04 (2115) : VM vide de nouveau, mémoire 2 Go" "$WB_PVE_HOST" \
  'qm config 2115 | grep -Eq "^memory: 2048$" && qm config 2115 | grep -Eq "^name: bm04$"'
_m11_e14_statut() { [[ "$(_m11p_equipement bm04 | jq -r '.status.value')" == planned ]]; }
check_cmd "NetBox : bm04 à l'état planned" _m11_e14_statut
