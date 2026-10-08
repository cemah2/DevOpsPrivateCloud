# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
#
# check-E30.sh — M07-E30 « La matrice des flux v2 »
# Lecture seule : copies de travail (matrice, doc), gw01/gw02/lb01/lb02/runner01 (admin + sudo -n,
# essais de connexion TCP sans données), API GitLab.

# shellcheck source=_m07-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-production.sh"

title "M07-E30 — La matrice des flux v2"
require_cmd yq ssh

_m07_mat="$_M07P_ANSIBLE/inventories/lab/group_vars/role_routeur/pare_feu.yml"
_m07_doc="$_M07P_DEPOT/docs/socle/matrice-flux.md"

title "La matrice en code"
check_output "chaque règle a un motif et une référence" '^0$' \
  yq '[.pare_feu_entree[], .pare_feu_transit[]] | map(select(.motif == null or .ref == null)) | length' "$_m07_mat"
check_output "plus de règle visant le giaddr de gw01 (10.10.99.1)" '^0$' \
  yq '[.pare_feu_entree[], .pare_feu_transit[]] | map(select(.destination == "10.10.99.1")) | length' "$_m07_mat"
check_cmd "aucune matrice propre à une passerelle (host_vars/gw0X/pare_feu.yml)" bash -c \
  '! ls "$1"/inventories/lab/host_vars/gw0[12]/pare_feu.yml >/dev/null 2>&1' _ "$_M07P_ANSIBLE"
for _m07_h in gw01 gw02; do
  check_ssh "$_m07_h : la configuration chargée est valide (nft -c)" "$_m07_h" 'sudo -n nft -c -f /etc/nftables.conf'
done
check_cmd "gw01 et gw02 chargent le même jeu de règles" _m07p_rulesets_identiques

title "Flux du module : seulement depuis les sources prévues"
check_ssh_output "BGP (179) accepté de sources précises seulement" gw01 'tcp dport 179 accept' 'sudo -n nft list chain inet filter input'
check_ssh "aucune règle n'accepte 179 sans source" gw01 \
  '! sudo -n nft list chain inet filter input | grep "dport 179" | grep -vq "saddr"'
check_cmd "runner01 → port 179 de gw01 (10.10.20.2) : fermé" _m07p_port_ferme runner01 10.10.20.2 179
check_cmd "runner01 → port 179 de gw02 (10.10.20.3) : fermé" _m07p_port_ferme runner01 10.10.20.3 179
check_ssh "VRRP n'est accepté que depuis des sources explicites" gw01 \
  '! sudo -n nft list chain inet filter input | grep -E "l4proto (112|vrrp)" | grep -vq "saddr"'

title "La DMZ filtre ses entrées"
for _m07_h in lb01 lb02; do
  check_ssh_output "$_m07_h : filtrage local en politique drop" "$_m07_h" 'hook input .*policy drop' \
    'sudo -n nft list table inet filtre_local'
done
for _m07_l in 10.10.70.10 10.10.70.11; do
  check_cmd "depuis gw01 (DMZ) → $_m07_l:22 : fermé" _m07p_port_ferme gw01 "$_m07_l" 22
  check_cmd "depuis gw01 (DMZ) → $_m07_l:443 : ouvert" _m07p_port_ouvert gw01 "$_m07_l" 443
done

title "La documentation suit le code"
check_cmd "docs/socle/matrice-flux.md présent et marqué comme généré" bash -c 'grep -q "ms-matrice-flux" "$1"' _ "$_m07_doc"
if command -v ms-matrice-flux >/dev/null 2>&1; then
  check_cmd "matrice-flux.md à jour par rapport à la matrice (ms-matrice-flux --verifier)" \
    ms-matrice-flux --verifier "$_m07_doc" "$_m07_mat"
else
  check_cmd "ms-matrice-flux installé sur adm01" false
fi
check_cmd "CI de plateforme/ansible : un job vérifie la matrice publiée" bash -c \
  'grep -rqs "ms-matrice-flux" "$1"/.gitlab-ci.yml "$1"/ci/ 2>/dev/null' _ "$_M07P_ANSIBLE"
