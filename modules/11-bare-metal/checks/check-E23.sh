# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
# check-E23.sh — M11-E23 « Sous le capot : un démarrage PXE paquet par paquet » : compte rendu sur
# main, structuré et complet ; aucune capture en cours ni fichier de capture dans un dépôt. Lecture seule.

# shellcheck source=_m11-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-expert.sh"

title "M11-E23 — Démarrage PXE sur le fil"
require_cmd curl jq ssh git

_m11_e23_cr="$(_m11p_gitlab_brut plateforme/medisphere docs/provisioning/analyses/demarrage-pxe.md)" || true
check_cmd "docs/provisioning/analyses/demarrage-pxe.md sur main de plateforme/medisphere" test -n "$_m11_e23_cr"
check_output "section sur le démarrage BIOS" '^## .*BIOS' printf '%s\n' "$_m11_e23_cr"
check_output "section sur le démarrage UEFI" '^## .*UEFI' printf '%s\n' "$_m11_e23_cr"
check_output "section « Réponses aux questions »" '^## Réponses aux questions' printf '%s\n' "$_m11_e23_cr"
check_cmd "champs et options cités (option 93, user-class/option 77, giaddr, RRQ, OACK, blksize, SNI, TLS)" \
  bash -c 'for m in "93" "77" giaddr RRQ OACK blksize SNI TLS; do grep -qi -- "$m" <<<"$1" || exit 1; done' _ "$_m11_e23_cr"
check_cmd "aucune clé privée ni jeton dans le compte rendu" \
  bash -c '! grep -Eq "PRIVATE KEY|Bearer [A-Za-z0-9]|PVEAPIToken=" <<<"$1"' _ "$_m11_e23_cr"

for _m11_e23_h in pxe01 dns01 gw01 gw02; do
  if [[ "$_m11_e23_h" == gw02 ]] && ! remote gw02 true >/dev/null 2>&1; then continue; fi
  check_ssh "$_m11_e23_h : aucune capture tcpdump en cours" "$_m11_e23_h" '! pgrep -x tcpdump >/dev/null'
done
check_ssh "pve01 : aucune capture tcpdump en cours" "$WB_PVE_HOST" '! pgrep -x tcpdump >/dev/null'
check_ssh "pve01 : aucun fichier de capture laissé dans /root ni /tmp" "$WB_PVE_HOST" \
  '[ -z "$(find /root /tmp -maxdepth 2 \( -name "*.pcap" -o -name "*.pcapng" \) 2>/dev/null)" ]'
for _m11_e23_d in "${WB_DEPOT:-$HOME/medisphere}" "$_m11p_src/provisioning"; do
  check_cmd "aucun fichier de capture suivi par Git dans $_m11_e23_d" \
    bash -c 'cd "$1" && [ -z "$(git ls-files "*.pcap" "*.pcapng" "*.cap")" ]' _ "$_m11_e23_d"
done
