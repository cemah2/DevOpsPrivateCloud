# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
# check-E19.sh — M13-E19 « Panne : impossible de tirer l'image » : les tirages des témoins passent
# (sonde en mode lecture), la visibilité des projets et l'endpoint du cache sont sains, runner02 vérifie
# le certificat de Harbor. Avant la première injection (témoins absents) : prérequis seulement.

# shellcheck source=_m13-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-expert.sh"

title "M13-E19 — Les tirages passent"
require_cmd jq curl

check_cmd "Harbor répond « healthy »" _m13p_sante
check_cmd "identité des pannes ~/.config/workbook/harbor-pannes.env présente (600)" _m13x_harbor_pannes_ok
check_ssh "runner02 : Docker actif" "$_m13x_runner" 'systemctl is-active -q docker'
check_ssh "runner02 : racine MédiSphère dans le magasin système" "$_m13x_runner" \
  'test -s /usr/local/share/ca-certificates/medisphere-root-ca.crt && grep -rqs "MédiSphère\|MediSphere\|medisphere" /etc/ssl/certs/ca-certificates.crt /usr/local/share/ca-certificates/medisphere-root-ca.crt'
check_ssh "runner02 : certificat de Harbor vérifié par la racine (openssl)" "$_m13x_runner" \
  'echo | timeout 10 openssl s_client -connect '"$_M13P_REGISTRE_NOM"':443 -servername '"$_M13P_REGISTRE_NOM"' -verify_return_error >/dev/null 2>&1'
check_ssh "runner02 : aucun registre « insecure » dans la configuration de Docker" "$_m13x_runner" \
  '! sudo -n grep -qs "insecure-registries" /etc/docker/daemon.json || sudo -n grep -Eq "\"insecure-registries\"[[:space:]]*:[[:space:]]*\[[[:space:]]*\]" /etc/docker/daemon.json'
check_cmd "endpoint amont du cache dockerhub « healthy »" _m13x_endpoint_cache_sain

if _m13x_temoins; then
  check_cmd "wb-sonde est privé" _m13p_projet_meta wb-sonde public false
  check_cmd "wb-sonde-public est public" _m13p_projet_meta wb-sonde-public public true
  check_cmd "sonde : tirage privé avec robot\$wb-sonde-tirage" _m13x_sonde_lecture tirage
  check_cmd "sonde : tirage anonyme de wb-sonde-public" _m13x_sonde_lecture public
  check_cmd "sonde : tirage par le cache dockerhub" _m13x_sonde_lecture cache
else
  skip "contrôles des témoins" "témoins pas encore créés (ils le sont à la première injection)"
fi
check_cmd "docs/registre/runbooks : RB-133 publié" _m13p_doc_prefixe docs/registre/runbooks RB-133
check_cmd "panne M13-E19 close (lab/bin/break 13 19 --annuler après réparation)" _m13p_aucune_panne_active E19
