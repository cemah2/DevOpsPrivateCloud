# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
# check-E38.sh — M06-E38 « Panne : connexion SSH par certificat refusée » : le certificat
# d'utilisateur de adm01 est valide et accepté partout, la configuration de sshd est cohérente avec
# la CA d'utilisateur, et l'accès de secours existe. Lecture seule.

# shellcheck source=_m06-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-expert.sh"

title "M06-E38 — SSH par certificat"
require_cmd ssh ssh-keygen

# _m06_e38_cert — premier certificat d'utilisateur de adm01 (~/.ssh/*-cert.pub).
_m06_e38_cert() {
  local c
  for c in "$HOME"/.ssh/*-cert.pub; do
    [[ -f "$c" ]] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}
# _m06_e38_valide — le certificat est valide maintenant et porte le principal admin.
_m06_e38_valide() {
  local c l fin
  c="$(_m06_e38_cert)" || return 1
  l="$(ssh-keygen -Lf "$c")" || return 1
  grep -Eq '^[[:space:]]+admin$' <<<"$l" || return 1
  fin="$(sed -nE 's/.*Valid: from [^ ]+ to ([0-9T:-]+).*/\1/p' <<<"$l")"
  [[ -n "$fin" ]] && (($(date -d "$fin" +%s) > $(date +%s)))
}
# _m06_e38_ca — empreinte de la CA qui a signé le certificat de adm01.
_m06_e38_ca() {
  local c
  c="$(_m06_e38_cert)" || return 1
  ssh-keygen -Lf "$c" | sed -nE 's/.*Signing CA: [A-Z0-9-]+ (SHA256:[^ ]+).*/\1/p'
}

check_cmd "adm01 : certificat d'utilisateur valide, principal admin" _m06_e38_valide
_m06_e38_fp="$(_m06_e38_ca 2>/dev/null || true)"
for _m06_e38_h in dns01 ca01 git01 nbx01 s3-01 runner01 dns02; do
  if [[ "$_m06_e38_h" == dns02 ]] && ! _m06x_existe dns02; then
    skip "dns02" "absent (M06-E24)"
    continue
  fi
  check_cmd "$_m06_e38_h : nouvelle connexion SSH acceptée (sans multiplexage)" _m06x_ssh_neuf "$_m06_e38_h"
  check_ssh "$_m06_e38_h : TrustedUserCAKeys contient la CA qui signe ton certificat" "$_m06_e38_h" \
    't=$(sudo -n sshd -T | awk "\$1 == \"trustedusercakeys\" { print \$2 }"); [ -n "$t" ] && [ "$t" != none ] && ssh-keygen -lf "$t" | grep -qF "'"$_m06_e38_fp"'" && [ -n "'"$_m06_e38_fp"'" ]'
  check_ssh "$_m06_e38_h : algorithmes de certificats acceptés par sshd" "$_m06_e38_h" \
    'sudo -n sshd -T | awk "\$1 == \"pubkeyacceptedalgorithms\" { print \$2 }" | grep -q "ssh-ed25519-cert-v01@openssh.com"'
  check_ssh "$_m06_e38_h : compte de secours présent" "$_m06_e38_h" 'getent passwd secours >/dev/null'
done
check_ssh "agent QEMU de nbx01, ca01 et dns02 joignable (accès de secours)" "$WB_PVE_HOST" \
  'for i in 1003 1005; do qm guest cmd "$i" ping || exit 1; done; ! qm status 1008 >/dev/null 2>&1 || qm guest cmd 1008 ping'
check_cmd "panne M06-E38 close (lab/bin/break 06 38 --annuler après réparation)" _m06x_aucune_panne_active E38
