# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E19.sh — M06-E19 : Certificats SSH d'hôte : fin de la confiance aveugle
# À lancer depuis adm01. Lecture seule : ssh-keyscan, connexions SSH avec un known_hosts
# temporaire qui ne contient QUE la CA (dans un dossier temporaire effacé à la sortie).

# shellcheck source=_m06-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-operationnel.sh"

title "M06-E19 — Certificats SSH d'hôte : fin de la confiance aveugle"
require_cmd ssh ssh-keyscan ssh-keygen

_m06o_kh="$HOME/.ssh/known_hosts"
_m06o_ca_ligne="$(grep -h '^@cert-authority' "$_m06o_kh" /etc/ssh/ssh_known_hosts 2>/dev/null | head -n 1 || true)"
check_cmd "adm01 : une ligne @cert-authority dans known_hosts" test -n "$_m06o_ca_ligne"
printf '%s\n' "$_m06o_ca_ligne" >"$_M06O_TMP/kh_ca"

# Certificat présenté par l'hôte (ssh-keyscan -c), lu par ssh-keygen -L.
_m06o_cert_hote() {
  # (ssh-keyscan -c n'écrit pas le nom d'hôte devant un certificat : on cherche le type « …-cert-v01 ».)
  ssh-keyscan -T "$WB_TIMEOUT" -c -t ed25519 "$1" 2>/dev/null \
    | awk '{ for (i = 1; i < NF; i++) if ($i ~ /-cert-v01@openssh\.com$/) { print $i, $(i + 1); exit } }' \
    | ssh-keygen -L -f - 2>/dev/null || true
}
# Connexion qui ne fait confiance qu'à la CA (ni multiplexage, ni known_hosts habituel).
_m06o_ssh_ca() {
  ssh -o BatchMode=yes -o ConnectTimeout="$WB_TIMEOUT" -o ControlPath=none -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="$_M06O_TMP/kh_ca" -o GlobalKnownHostsFile=/dev/null "admin@$1" true
}
# Clés BRUTES du socle restées dans ~/.ssh/known_hosts (ssh-keygen -F trouve aussi les entrées hachées).
_m06o_sans_cle_brute() {
  local ip
  grep -q '^@cert-authority' "$_m06o_kh" 2>/dev/null || return 1
  for ip in "${_M06O_IP[@]}"; do
    [[ "$ip" == 10.10.10.10 ]] && continue
    ssh-keygen -F "$ip" -f "$_m06o_kh" 2>/dev/null | grep -v '^#' | grep -qv '@cert-authority' && return 1
  done
  return 0
}

for _m06o_h in $_M06O_DISTANTS; do
  _m06o_ip="${_M06O_IP[$_m06o_h]}"
  _m06o_cert="$(_m06o_cert_hote "$_m06o_ip")"
  check_output "$_m06o_h : présente un certificat d'hôte" 'host certificate' echo "$_m06o_cert"
  check_cmd "$_m06o_h : principaux = nom court, nom complet et adresse $_m06o_ip" \
    bash -c 'for p in "$2" "$2.par1.medisphere.internal" "$3"; do grep -Eq "^[[:space:]]+${p//./\\.}$" <<<"$1" || exit 1; done' \
    _ "$_m06o_cert" "$_m06o_h" "$_m06o_ip"
  check_cmd "$_m06o_h : certificat de 30 jours au plus, valide maintenant" \
    bash -c 'v="$(sed -nE "s/^[[:space:]]+Valid: from ([^ ]+) to ([^ ]+)$/\1 \2/p" <<<"$1")"; [[ -n "$v" ]] || exit 1;
             d="${v% *}"; f="${v#* }"; n="$(date +%s)";
             (( $(date -d "$f" +%s) > n && $(date -d "$d" +%s) <= n && $(date -d "$f" +%s) - $(date -d "$d" +%s) <= 31*86400 ))' \
    _ "$_m06o_cert"
  check_cmd "$_m06o_h : connexion avec un known_hosts qui ne contient que la CA (adresse IP)" _m06o_ssh_ca "$_m06o_ip"
  check_ssh "$_m06o_h : minuterie ssh-cert-hote.timer active" "$_m06o_h" 'systemctl is-active --quiet ssh-cert-hote.timer'
done

check_cmd "adm01 : plus aucune clé d'hôte brute du socle dans ~/.ssh/known_hosts" _m06o_sans_cle_brute
check_cmd "projet Ansible : inventories/lab/known_hosts ne contient que la CA d'hôte" \
  bash -c 'grep -q "^@cert-authority" "$1" && ! grep -Ev "^(#|@cert-authority|$)" "$1" | grep -q .' \
  _ "$_M06O_ANSIBLE/inventories/lab/known_hosts"
