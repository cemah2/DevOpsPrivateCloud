# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E34.sh — M10-E34 « Un environnement complet en temps limité » (dossier CHG-1160, MédiNotif)
# À lancer à T4, AVANT le retrait. Lecture seule : Keystone, quotas, réseau, instances, volume,
# connexion TCP au port 22 de l'IP flottante depuis adm01. Le retrait est vérifié par M10-E46.

# shellcheck source=_m10-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-production.sh"

title "M10-E34 — Un environnement complet en temps limité (medinotif-essai)"
require_cmd openstack jq

_m10_pr="$(_m10p_os project show medinotif-essai --domain medisphere 2>/dev/null || echo null)"
_m10_pj="$(jq -r '.id // empty' <<<"$_m10_pr" 2>/dev/null || true)"

title "Identité et projet (exigences 1 à 3)"
check_cmd "projet medinotif-essai (domaine medisphere), description qui cite CHG-1160" \
  jq -e '.description // "" | test("CHG-1160")' <<<"$_m10_pr"
_m10_quotas() {
  local q
  q="$(_m10p_os quota show "$_m10_pj")" || return 1
  jq -e 'if type == "array" then (map({(.Resource): .Limit}) | add) else . end
    | .instances == 3 and .cores == 4 and .ram == 6144 and .volumes == 2 and .gigabytes == 30
      and ((.["floating-ips"] // .floatingip // .floating_ips) == 1) and .routers == 1 and .networks == 2' >/dev/null <<<"$q"
}
check_cmd "quotas : 3 instances, 4 vCPU, 6144 Mo, 2 volumes / 30 Go, 1 IP flottante, 1 routeur, 2 réseaux" _m10_quotas
_m10_roles() {
  local r
  r="$(_m10p_os role assignment list --project "$_m10_pj" --names)" || return 1
  jq -e 'any(.[]; .Group == "equipe-medinotif@medisphere" and .Role == "member")
     and any(.[]; .User == "lucas.martin@medisphere" and .Role == "reader")
     and (any(.[]; .User == "lucas.martin@medisphere" and (.Role == "member" or .Role == "admin")) | not)' >/dev/null <<<"$r"
}
check_cmd "rôles : groupe equipe-medinotif member, lucas.martin reader (et rien de plus)" _m10_roles

title "Réseau (exigences 4 à 6)"
_m10_sn() {
  local s
  s="$(_m10p_os subnet show "$(_m10p_id subnet medinotif-sn "$_m10_pj")")" || return 1
  jq -e '.cidr == "192.168.60.0/24" and (.dns_nameservers | tostring | test("10\\.10\\.20\\.10")) and (.dns_nameservers | tostring | test("10\\.10\\.20\\.16"))' >/dev/null <<<"$s"
}
check_cmd "sous-réseau medinotif-sn : 192.168.60.0/24, résolveurs du socle" _m10_sn
_m10_rt() {
  local r e
  r="$(_m10p_os router show "$(_m10p_id router medinotif-rt "$_m10_pj")")" || return 1
  e="$(_m10p_os network show ext-net | jq -r .id)" || return 1
  jq -e --arg e "$e" '.external_gateway_info.network_id == $e and (.interfaces_info | length) >= 1' >/dev/null <<<"$r"
}
check_cmd "routeur medinotif-rt relié à ext-net et au sous-réseau" _m10_rt
_m10_sg() {
  local r
  r="$(_m10p_os security group rule list "$(_m10p_id "security group" medinotif-ssh "$_m10_pj")")" || return 1
  jq -e '[.[] | select(.Direction == "ingress")] as $e
    | ($e | all(.; (.["IP Range"] // "") != "0.0.0.0/0"))
      and ($e | any(.; .["IP Protocol"] == "tcp" and .["IP Range"] == "10.10.10.0/24" and (.["Port Range"] | tostring | test("^22"))))
      and ($e | any(.; .["IP Protocol"] == "tcp" and .["IP Range"] == "10.255.1.0/24"))
      and ($e | any(.; .["IP Protocol"] == "icmp" and (.["Remote Security Group"] // null) != null))
      and ($e | any(.; .["IP Protocol"] == "tcp" and (.["Remote Security Group"] // null) != null))' >/dev/null <<<"$r"
}
check_cmd "groupe medinotif-ssh : SSH depuis MGMT, VPN et membres ; ICMP entre membres ; rien vers 0.0.0.0/0" _m10_sg

title "Calcul et stockage (exigences 7 à 10)"
_m10_srv="$(_m10p_os server list --project "$_m10_pj" --long 2>/dev/null || echo '[]')"
check_cmd "medinotif-worker01 ACTIVE (Rocky Linux 10)" \
  jq -e 'any(.[]; .Name == "medinotif-worker01" and .Status == "ACTIVE" and ((.["Image Name"] // "") | test("(?i)rocky")))' <<<"$_m10_srv"
check_cmd "medinotif-worker02 ACTIVE (Debian 13)" \
  jq -e 'any(.[]; .Name == "medinotif-worker02" and .Status == "ACTIVE" and ((.["Image Name"] // "") | test("(?i)debian")))' <<<"$_m10_srv"
check_cmd "worker02 sans IP flottante" \
  jq -e 'any(.[]; .Name == "medinotif-worker02" and (.Networks | tostring | test("10\\.10\\.52\\.") | not))' <<<"$_m10_srv"
_m10_fip="$(jq -r '.[] | select(.Name == "medinotif-worker01") | .Networks | tostring' <<<"$_m10_srv" 2>/dev/null \
  | grep -oE '10\.10\.52\.[0-9]+' | head -n 1 || true)"
check_output "worker01 : une IP flottante (${_m10_fip:-aucune})" '^10\.10\.52\.' printf '%s\n' "${_m10_fip:-}"
check_port "worker01 : SSH joignable depuis adm01 par l'IP flottante" "${_m10_fip:-0.0.0.0}" 22
_m10_vol() {
  local v sid
  v="$(_m10p_os volume show "$(_m10p_id volume medinotif-file "$_m10_pj")")" || return 1
  sid="$(jq -r '.[] | select(.Name == "medinotif-worker01") | .ID' <<<"$_m10_srv")"
  [[ -n "$sid" ]] && jq -e --arg s "$sid" '.size == 10 and any(.attachments[]?; .server_id == $s)' >/dev/null <<<"$v"
}
check_cmd "volume medinotif-file (10 Go) attaché à worker01" _m10_vol
_m10_cle() {
  local w
  w="$(_m10p_os server show "$(jq -r '.[] | select(.Name == "medinotif-worker01") | .ID' <<<"$_m10_srv")")" || return 1
  jq -e '.key_name == "medinotif-cle"' >/dev/null <<<"$w"
}
check_cmd "worker01 créé avec la paire de clés medinotif-cle" _m10_cle
