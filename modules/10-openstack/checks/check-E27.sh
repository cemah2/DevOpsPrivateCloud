# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E27.sh — M10-E27 « Sécuriser OpenStack »
# Lecture seule : catalogue Keystone, certificats servis par les VIP, configuration générée sur
# osctl01 (sudo -n), options des comptes de service, GitLab.

# shellcheck source=_m10-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-production.sh"

title "M10-E27 — Sécuriser OpenStack"
require_cmd openstack jq openssl ssh

title "TLS des VIP"
_m10_internes_https() {
  local l
  l="$(_m10p_os endpoint list --interface internal)" || return 1
  jq -e --arg n "$_M10P_NOM_INT" 'type == "array" and length > 0 and all(.[]; .URL | startswith("https://" + $n))' >/dev/null <<<"$l"
}
check_cmd "catalogue : tous les points « internal » en https://$_M10P_NOM_INT" _m10_internes_https
for _m10_p in 5000 8774 9696; do
  check_cmd "VIP interne :$_m10_p : certificat PKI MédiSphère, nom correct, ≤ 31 jours, > 10 jours restants" \
    _m10p_cert_vip "$_M10P_NOM_INT" "$_M10P_VIP_INT" "$_m10_p"
done
for _m10_p in 443 5000; do
  check_cmd "VIP externe :$_m10_p : certificat PKI MédiSphère, nom correct, ≤ 31 jours, > 10 jours restants" \
    _m10p_cert_vip "$_M10P_NOM_EXT" "$_M10P_VIP_EXT" "$_m10_p"
done
check_ssh "osctl01 : racine MédiSphère copiée dans les conteneurs (keystone)" osctl01 \
  'sudo -n docker exec keystone sh -c "ls /usr/local/share/ca-certificates/ | grep -q kolla-customca-"'

title "Renouvellement automatique"
_m10_acme() {
  remote osctl01 'for c in letsencrypt_lego letsencrypt_webserver; do sudo -n docker ps --filter "name=^$c\$" --filter status=running -q | grep -q . || exit 1; done' >/dev/null 2>&1
}
_m10_alternative() {
  _m10p_fichier_contient plateforme/medisphere docs/cloud/securite.md 'alternative' 'renouvel'
}
if _m10_acme; then
  check_cmd "conteneurs ACME de Kolla (letsencrypt_lego, letsencrypt_webserver) en service" _m10_acme
  # Chaque passage de lego renouvelle (seuil par défaut de lego, 30 jours) : le planning de la
  # crontab générée ne doit pas lancer plus d'un passage par jour (heure fixe, pas « */4 »).
  check_ssh "client ACME : au plus un passage par jour (pas de renouvellement toutes les 4 h)" osctl01 \
    'h=$(sudo -n awk '"'"'/letsencrypt-certificates/ && !/^#/ {print $2}'"'"' /etc/kolla/letsencrypt-lego/crontab) || exit 1
     [ -n "$h" ] || exit 1
     ! printf "%s\n" $h | grep -Evq "^[0-9]+$"'
else
  skip "conteneurs ACME de Kolla" "absents : alternative documentée attendue"
  check_cmd "securite.md documente l'alternative de renouvellement" _m10_alternative
fi

title "Keystone et Horizon"
check_ssh "keystone.conf généré : lockout_failure_attempts = 5" osctl01 \
  'sudo -n grep -Eq "^lockout_failure_attempts[[:space:]]*=[[:space:]]*5$" /etc/kolla/keystone/keystone.conf'
check_ssh "keystone.conf généré : lockout_duration = 900" osctl01 \
  'sudo -n grep -Eq "^lockout_duration[[:space:]]*=[[:space:]]*900$" /etc/kolla/keystone/keystone.conf'
_m10_dispense() {
  local u
  u="$(_m10p_os user show "$1" --domain Default)" || return 1
  jq -e '.options.ignore_lockout_failure_attempts == true' >/dev/null <<<"$u"
}
for _m10_u in nova neutron glance cinder placement svc-supervision svc-tofu; do
  check_cmd "compte $_m10_u : dispensé du verrouillage" _m10_dispense "$_m10_u"
done
_m10_essai_absent() {
  local l
  l="$(_m10p_os user list --domain medisphere)" || return 1
  jq -e 'type == "array" and (any(.[]; .Name == "essai-verrou") | not)' >/dev/null <<<"$l"
}
check_cmd "le compte essai-verrou n'existe plus" _m10_essai_absent
check_ssh "Horizon : sessions de 30 minutes (SESSION_TIMEOUT = 1800)" osctl01 \
  'sudo -n grep -rEqs "^SESSION_TIMEOUT[[:space:]]*=[[:space:]]*1800" /etc/kolla/horizon/'
check_ssh "Horizon : limite absolue, non prolongée par l'activité (SESSION_REFRESH = False)" osctl01 \
  'sudo -n grep -rEqs "^SESSION_REFRESH[[:space:]]*=[[:space:]]*False" /etc/kolla/horizon/'

title "Documentation et ménage"
check_cmd "plateforme/medisphere : docs/cloud/securite.md (ce qui reste en clair, rotation)" \
  _m10p_fichier_contient plateforme/medisphere docs/cloud/securite.md 'rabbitmq' 'rotation'
check_cmd "plus aucune instance secu-essai*" _m10p_aucune_instance secu-essai
