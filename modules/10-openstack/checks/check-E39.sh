# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E39.sh — M10-E39 « Panne : plus personne ne s'authentifie » : Keystone émet des jetons,
# ses clés fernet appartiennent au compte du service, memcached sert, Horizon répond. Lecture seule.
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant

# shellcheck source=_m10-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-expert.sh"

title "M10-E39 — L'authentification fonctionne"
require_cmd openstack curl ssh

check_cmd "cloud $_m10x_cloud_admin : un jeton est émis" _m10x_os token issue -f value -c id
check_cmd "cloud $_m10x_cloud_projet : un jeton est émis" _m10x_osp token issue -f value -c id
for _m10_e39_c in keystone keystone_fernet memcached horizon; do
  check_cmd "$_m10x_ctl : $_m10_e39_c en service (et non « unhealthy »)" _m10x_ctr_sain "$_m10x_ctl" "$_m10_e39_c"
done
check_ssh "$_m10x_ctl : clés fernet présentes et propriété du compte keystone" "$_m10x_ctl" '
  d=$(sudo -n docker volume inspect -f "{{.Mountpoint}}" keystone_fernet_tokens) && [ -n "$d" ] || exit 1
  sudo -n test -f "$d/0" || exit 1
  [ -z "$(sudo -n find "$d" -mindepth 1 -maxdepth 1 -type f -user root)" ]'
check_ssh "$_m10x_ctl : memcached écoute sur le port 11211" "$_m10x_ctl" 'ss -ltn | grep -q ":11211 "'
check_output "Horizon : page de connexion en 200, certificat vérifié" '^200$' _m10x_https_code /auth/login/
check_cmd "panne M10-E39 close (lab/bin/break 10 39 --annuler après réparation)" _m10x_aucune_panne_active E39
