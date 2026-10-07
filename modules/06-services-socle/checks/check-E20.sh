# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E20.sh — M06-E20 : Certificats SSH d'utilisateur et bastion adm01
# À lancer depuis adm01, avec le certificat du jour chargé (ms-ssh-cert). Lecture seule : une
# connexion SSH sans multiplexage par hôte (pour lire, dans son journal, comment elle a été acceptée).

# shellcheck source=_m06-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-operationnel.sh"

title "M06-E20 — Certificats SSH d'utilisateur et bastion adm01"
require_cmd ssh ssh-keygen

_m06o_cert="$HOME/.ssh/id_ed25519-cert.pub"
_m06o_pub="$HOME/.ssh/id_ed25519.pub"
_m06o_lu="$(ssh-keygen -L -f "$_m06o_cert" 2>/dev/null || true)"

_m06o_cert_valide() {
  local v d f n
  v="$(sed -nE 's/^[[:space:]]+Valid: from ([^ ]+) to ([^ ]+)$/\1 \2/p' <<<"$_m06o_lu")"
  [[ -n "$v" ]] || return 1
  d="${v% *}"; f="${v#* }"; n="$(date +%s)"
  (( $(date -d "$f" +%s) > n && $(date -d "$d" +%s) <= n && $(date -d "$f" +%s) - $(date -d "$d" +%s) <= 16 * 3600 + 120 ))
}
# Clé publique quotidienne de adm01 (deux premiers champs) absente des clés autorisées de admin.
_m06o_cle_quotidienne="$(awk '{ print $1, $2 }' "$_m06o_pub" 2>/dev/null || true)"

check_cmd "adm01 : certificat d'utilisateur présent (~/.ssh/id_ed25519-cert.pub)" test -s "$_m06o_cert"
check_output "le certificat porte le principal admin" '^[[:space:]]+admin$' echo "$_m06o_lu"
check_cmd "le certificat est valide maintenant, pour 16 h au plus" _m06o_cert_valide

for _m06o_h in $_M06O_DISTANTS; do
  check_ssh_output "$_m06o_h : sshd applique TrustedUserCAKeys et AuthorizedPrincipalsFile" "$_m06o_h" \
    'trustedusercakeys /.*authorizedprincipalsfile /|authorizedprincipalsfile /.*trustedusercakeys /' \
    'sudo -n sshd -T 2>/dev/null | grep -E "^(trustedusercakeys|authorizedprincipalsfile) " | tr "\n" " "'
  check_ssh "$_m06o_h : principaux du compte admin = admin et astreinte" "$_m06o_h" \
    'f="$(sudo -n sshd -T -C user=admin,host=x,addr=127.0.0.1 2>/dev/null | awk "\$1 == \"authorizedprincipalsfile\" { print \$2 }" | sed "s/%u/admin/")";
     [ -n "$f" ] && [ "$(sudo -n sort "$f" | tr "\n" " ")" = "admin astreinte " ]'
  check_ssh "$_m06o_h : la clé quotidienne de adm01 n'est plus autorisée pour admin" "$_m06o_h" \
    "! sudo -n grep -qF '${_m06o_cle_quotidienne:-cle-introuvable}' /home/admin/.ssh/authorized_keys"
  check_ssh "$_m06o_h : la clé ansible-ci reste autorisée (from=10.10.20.15)" "$_m06o_h" \
    'sudo -n grep -q "from=\"10.10.20.15\".*ansible-ci" /home/admin/.ssh/authorized_keys'
done

# Une connexion neuve sur dns01, puis la ligne du journal qui dit comment elle a été acceptée.
_m06o_preuve="$(ssh -o BatchMode=yes -o ControlPath=none -o ConnectTimeout="$WB_TIMEOUT" dns01 \
  'sleep 1; sudo -n journalctl -u ssh --since "-2min" --no-pager -o cat | grep "Accepted publickey for admin" | tail -n 1' 2>/dev/null || true)"
check_output "dns01 : connexion acceptée par CERTIFICAT (journal : ED25519-CERT … ID …)" 'ED25519-CERT .* ID .*\(serial [0-9]+\) CA ' \
  echo "$_m06o_preuve"

# Bastion : depuis le VPN (wg1), plus de transit SSH vers INFRA sans restriction de port.
check_ssh "gw01 : le VPN d'administration n'a plus de règle de transit sans port vers INFRA" gw01 \
  '! sudo -n nft list chain inet filter forward | grep -E "iifname \"wg1\"" | grep -E "ens19\.20" | grep -qvE "dport"'
check_ssh "gw01 : le VPN d'administration joint adm01 en SSH" gw01 \
  'sudo -n nft list chain inet filter forward | grep -E "iifname \"wg1\"" | grep -E "10\.10\.10\.10" | grep -q "dport 22"'
check_cmd "plateforme/outils : ms-ssh-cert publié sur main" _m06o_fichier_main "$_M06O_PROJET_OUTILS" bin/ms-ssh-cert
