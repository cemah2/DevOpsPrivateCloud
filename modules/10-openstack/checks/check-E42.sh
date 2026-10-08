# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E42.sh — M10-E42 « Panne : le tableau de bord est inaccessible » : Horizon répond derrière
# HAProxy avec le certificat step-ca, les VIP sont présentes, les conteneurs sont sains. Lecture seule.

# shellcheck disable=SC2016  # scripts bash -c : arguments passés en $1, $2

# shellcheck source=_m10-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-expert.sh"

title "M10-E42 — Le tableau de bord est accessible"
require_cmd curl openssl ssh

check_port "VIP externe $_m10x_vip_ext : port 443 ouvert" "$_m10x_vip_ext" 443
check_port "VIP interne $_m10x_vip_int : Keystone (5000) joignable" "$_m10x_vip_int" 5000
check_output "Horizon : page de connexion en 200, certificat vérifié par le magasin système" '^200$' \
  _m10x_https_code /auth/login/
check_cmd "certificat externe émis par l'intermédiaire MédiSphère, chaîne complète présentée" \
  bash -c 'c="$(openssl s_client -connect "$1:443" -servername "$2" -showcerts </dev/null 2>/dev/null)"
    [ "$(grep -c "BEGIN CERTIFICATE" <<<"$c")" -ge 2 ] || exit 1
    sed -n "/BEGIN CERTIFICATE/,/END CERTIFICATE/p" <<<"$c" | awk "{ print } /END CERTIFICATE/ { exit }" \
      | openssl x509 -noout -issuer -nameopt utf8,sep_comma_plus 2>/dev/null | grep -q "Intermediate CA"' \
  _ "$_m10x_vip_ext" "$_m10x_fqdn"
for _m10_e42_c in horizon haproxy keepalived; do
  check_cmd "$_m10x_ctl : $_m10_e42_c en service" _m10x_ctr_sain "$_m10x_ctl" "$_m10_e42_c"
done
check_cmd "panne M10-E42 close (lab/bin/break 10 42 --annuler après réparation)" _m10x_aucune_panne_active E42
