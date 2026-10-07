# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
# check-E37.sh — M06-E37 « Panne : certificat refusé » : certificats des services HTTPS du socle
# émis par la PKI et vérifiables, magasin de confiance et horloge de runner01 sains. Lecture seule.

# shellcheck source=_m06-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-expert.sh"

title "M06-E37 — Certificats acceptés partout"
require_cmd curl openssl ssh

for _m06_e37_s in "nbx01 443" "git01 443" "ca01 443" "s3-01 8333"; do
  read -r _m06_e37_h _m06_e37_p <<<"$_m06_e37_s"
  check_cmd "$_m06_e37_h:$_m06_e37_p : certificat vérifié par adm01" \
    _m06x_https_ok "$_m06_e37_h.$_m06x_zone" "${_m06x_ip[$_m06_e37_h]}" "$_m06_e37_p"
done
for _m06_e37_h in nbx01 git01; do
  check_cmd "$_m06_e37_h : chaîne complète, feuille émise par l'intermédiaire MédiSphère" \
    _m06x_emis_par_pki "$_m06_e37_h.$_m06x_zone" "${_m06x_ip[$_m06_e37_h]}"
done
check_ssh "runner01 : racine MédiSphère dans le magasin système" runner01 \
  'test -s /usr/local/share/ca-certificates/medisphere-root-ca.crt && test -L /etc/ssl/certs/medisphere-root-ca.pem'
check_ssh "runner01 : HTTPS vérifié vers GitLab" runner01 \
  "curl -sS -o /dev/null --max-time 10 https://git01.$_m06x_zone/users/sign_in"
_m06_e37_ecart() {
  local t d
  t="$(remote runner01 'date +%s' 2>/dev/null)" || return 1
  [[ "$t" =~ ^[0-9]+$ ]] || return 1
  d=$((t - $(date +%s)))
  ((d > -5 && d < 5))
}
check_cmd "runner01 : horloge à moins de 5 s de celle de adm01" _m06_e37_ecart
check_ssh "runner01 : chrony actif et synchronisé" runner01 \
  'systemctl is-active -q chrony && chronyc -n tracking | grep -Eq "^Leap status +: Normal"'
check_ssh "runner01 : gitlab-runner actif" runner01 'systemctl is-active -q gitlab-runner'
check_cmd "panne M06-E37 close (lab/bin/break 06 37 --annuler après réparation)" _m06x_aucune_panne_active E37
