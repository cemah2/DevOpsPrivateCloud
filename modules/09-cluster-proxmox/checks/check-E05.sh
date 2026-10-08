# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes : évaluées sur l'hôte distant
#
# check-E05.sh — M09-E05 : Deux nœuds et un arbitre : le QDevice
# À lancer depuis adm01. Lecture seule : pvecm et services sur hv01/hv02, corosync-qnetd, pare-feu
# et authorized_keys de pbs01 (root), règles de gw01 (sudo -n), copie de travail Ansible.
# Après M09-E08 (troisième nœud, QDevice retiré), les contrôles du QDevice sont ignorés.

# shellcheck source=_m09-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-decouverte.sh"

title "M09-E05 — Deux nœuds et un arbitre : le QDevice"

_m09d_e05_statut="$(_m09d_hv hv01 'pvecm status')"
_m09d_e05_noeuds="$(sed -nE 's/^Nodes:[[:space:]]+([0-9]+)$/\1/p' <<<"$_m09d_e05_statut")"

check_cmd "Fiche de changement CHG-1005 dans la documentation" \
  bash -c 'compgen -G "${WB_DEPOT:-$HOME/medisphere}/docs/*/changements/CHG-1005*" >/dev/null'

# --- Le QDevice en service (sauf après M09-E08) ---------------------------------------------------
_m09d_e05_qdevice() {
  # Le flux, écrit dans la matrice et chargé sur la bordure.
  check_cmd "Matrice des flux (group_vars/role_routeur/pare_feu.yml) : règle TCP 5403 vers pbs01, référence M09-E05" \
    bash -c 'grep -E "5403" "$1" | grep -q "M09-E05"' _ "$_M09D_MATRICE"
  check_ssh "gw01 : la règle TCP 5403 est chargée" gw01 'sudo -n nft list ruleset | grep -q "dport 5403"'
  check_cmd "pvecm status : drapeaux « Quorate Qdevice »" grep -Eq '^Flags:[[:space:]]+Quorate Qdevice' <<<"$_m09d_e05_statut"
  check_cmd "3 votes au total (deux nœuds + QDevice)" grep -Eq '^Total votes:[[:space:]]+3$' <<<"$_m09d_e05_statut"
  # Section « Membership information » : une ligne par nœud (0x0000000N), colonne Qdevice
  # « A,V,NMW » quand le QDevice est vivant (A) et vote pour ce nœud (V).
  check_cmd "Le QDevice est vivant et vote pour les deux nœuds (A,V)" \
    bash -c '[ "$(grep -E "^0x0+[1-9]" <<<"$1" | grep -c "A,V,")" -ge 2 ]' _ "$_m09d_e05_statut"
  for _m09d_e05_n in hv01 hv02; do
    check_ssh "$_m09d_e05_n : corosync-qdevice actif et activé" "$_m09d_e05_n" \
      'systemctl is-active --quiet corosync-qdevice && systemctl is-enabled --quiet corosync-qdevice'
  done
  check_ssh "pbs01 : corosync-qnetd actif" "$_M09D_PBS" 'systemctl is-active --quiet corosync-qnetd'
  check_ssh "pbs01 : qnetd voit le cluster hv-par1" "$_M09D_PBS" 'corosync-qnetd-tool -l | grep -q "hv-par1"'
  check_ssh "pbs01 : port 5403 ouvert aux seuls nœuds (10.10.10.51-53)" "$_M09D_PBS" \
    'r=$(nft list ruleset | grep "dport 5403"); [ -n "$r" ] && grep -q "10.10.10.5" <<<"$r" && ! grep -Eq "dport 5403 (ct state new )?accept" <<<"$(grep -v saddr <<<"$r")"'
  check_ssh "pbs01 : aucune clé de nœud hv0N laissée dans authorized_keys de root" "$_M09D_PBS" \
    '! grep -Eq "root@hv0[1-3]" /root/.ssh/authorized_keys'
}

if [[ "${_m09d_e05_noeuds:-0}" -ge 3 ]] && ! grep -q 'Qdevice' <<<"$_m09d_e05_statut"; then
  skip "QDevice du cluster à deux nœuds" "cluster à trois nœuds sans QDevice : état de M09-E08"
  check_ssh "pbs01 : aucune clé de nœud hv0N dans authorized_keys de root" "$_M09D_PBS" \
    '! grep -Eq "root@hv0[1-3]" /root/.ssh/authorized_keys'
else
  _m09d_e05_qdevice
fi
