# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
# check-E37.sh — M05-E37 « Panne : le backend d'état est inaccessible » : depuis adm01, le nom de
# s3-01 se résout comme dans le DNS, la passerelle S3 répond en TLS vérifié, l'identité tofu-etat a
# ses droits d'écriture, aucun filtrage ne bloque 8333, l'état se lit. Lecture seule.

# shellcheck source=_m05-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-expert.sh"

title "M05-E37 — Backend d'état joignable depuis adm01"
require_cmd tofu aws jq dig curl getent

_m05_e37_fqdn=s3-01.par1.medisphere.internal

_m05_e37_resolution() {
  [[ "$(getent hosts "$_m05_e37_fqdn" | awk '{ print $1; exit }')" == 10.10.20.14 ]]
}
# TLS vérifié avec le magasin système (aucun code 35/51/60 de curl, réponse HTTP quelconque).
_m05_e37_tls() {
  local rc=0
  curl -s -o /dev/null --max-time "$WB_TIMEOUT" "https://$_m05_e37_fqdn:8333/" || rc=$?
  ((rc == 0))
}
_m05_e37_lister() { _m05x_aws s3api list-objects-v2 --bucket "$_m05x_bucket" --max-items 1 >/dev/null 2>&1; }

check_dns "DNS : $_m05_e37_fqdn → 10.10.20.14" "$_m05_e37_fqdn" A '^10\.10\.20\.14$' 10.10.20.10
check_cmd "adm01 : le résolveur système donne la même adresse que le DNS (getent)" _m05_e37_resolution
check_port "adm01 → s3-01 : TCP/8333 joignable" 10.10.20.14 8333
check_cmd "adm01 → s3-01 : TLS vérifié par le magasin de certificats système" _m05_e37_tls
check_ssh "gw01 : aucune règle ne jette le trafic vers 8333" gw01 \
  '! sudo -n nft list ruleset | grep -Eq "dport 8333 .*(drop|reject)"'
check_ssh "s3-01 : l'identité tofu-etat a le droit d'écriture sur tofu-state" s3-01 \
  'pid=$(sudo -n ss -Hltnp "sport = :8333" | sed -n "s/.*pid=\([0-9][0-9]*\).*/\1/p" | head -n 1); [ -n "$pid" ] || exit 1
   c=$(sudo -n tr "\0" "\n" < /proc/$pid/cmdline | sed -n "s/^-*s3\.config=//p; s/^-*config=//p" | head -n 1)
   [ -z "$c" ] && exit 0
   sudo -n python3 -c "import json,sys; d=json.load(open(sys.argv[1])); ok=[i for i in d.get(\"identities\",[]) if i.get(\"name\")==\"tofu-etat\" and any(a.split(\":\")[0] in (\"Write\",\"Admin\") for a in i.get(\"actions\",[]))]; sys.exit(0 if ok else 1)" "$c"'
check_cmd "S3 : le compartiment tofu-state se liste avec les identifiants de s3-tofu.env" _m05_e37_lister
check_cmd "socle : l'état se lit (tofu state list)" _m05x_tofu "$_m05x_socle" state list
check_cmd "panne M05-E37 close (lab/bin/break 05 37 --annuler après réparation)" _m05x_aucune_panne_active E37
