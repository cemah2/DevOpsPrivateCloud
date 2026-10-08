# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E12.sh — M09-E12 : Consommer le Ceph de PAR1
# À lancer depuis adm01, deux fois : PENDANT l'exercice (stockage ceph-par1-rbd présent : contrôle
# du raccordement), puis APRÈS le rangement (stockage absent : contrôle du rangement).
# Lecture seule : storage.cfg, présence de fichiers sur les nœuds, « ceph auth get » et
# « ceph osd pool ls » sur ceph01 (sudo -n), API GitLab.

# shellcheck source=_m09-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-operationnel.sh"

title "M09-E12 — Consommer le Ceph de PAR1"
require_cmd jq

_m09o_s="$(_m09o_stockage_cfg ceph-par1-rbd)"
# Ceph de PAR1 (cephadm) : « ceph » du nœud _admin, ou par « cephadm shell ».
_m09o_ceph_par1() {
  remote "$_M09O_CEPH" "if command -v ceph >/dev/null; then sudo -n ceph $1; else sudo -n cephadm shell -- ceph $1; fi" 2>/dev/null || true
}
_m09o_par1_ok=0
remote "$_M09O_CEPH" true >/dev/null 2>&1 && _m09o_par1_ok=1

if [[ -n "$_m09o_s" ]]; then
  echo "  (stockage ceph-par1-rbd présent : contrôle du RACCORDEMENT ; relance après le rangement)"
  check_output "ceph-par1-rbd : type rbd" '^rbd: ceph-par1-rbd' echo "$_m09o_s"
  check_cmd "ceph-par1-rbd : les trois moniteurs 10.10.30.51, .52, .53" bash -c \
    'm="$(sed -n "s/^[[:space:]]*monhost //p" <<<"$1")"; for i in 51 52 53; do grep -q "10\.10\.30\.$i" <<<"$m" || exit 1; done' _ "$_m09o_s"
  check_output "ceph-par1-rbd : pool hv-par1" '^[[:space:]]+pool hv-par1$' echo "$_m09o_s"
  check_output "ceph-par1-rbd : identité hv-par1 (sans « client. », pas admin)" '^[[:space:]]+username hv-par1$' echo "$_m09o_s"
  check_cmd "ceph-par1-rbd actif sur les trois nœuds" _m09o_stockage_actif_partout ceph-par1-rbd
  check_ssh "le trousseau est rangé par Proxmox dans /etc/pve/priv/ceph/ceph-par1-rbd.keyring" "$(_m09o_noeud)" \
    'grep -q "client.hv-par1" /etc/pve/priv/ceph/ceph-par1-rbd.keyring'
  for _m09o_n in $_M09O_NOEUDS; do
    check_ssh "$_m09o_n : aucune autre copie de la clé client.hv-par1 (/root, /etc/ceph, /tmp)" "$_m09o_n" \
      '! grep -rlsq "client.hv-par1" /root /etc/ceph /tmp'
  done
  if (( _m09o_par1_ok )); then
    # Seules les lignes « caps » sortent de ceph01 : la clé n'est ni transférée ni affichée.
    _m09o_a="$(_m09o_ceph_par1 'auth get client.hv-par1 2>/dev/null | grep caps')"
    check_output "ceph-par1 : client.hv-par1 a « profile rbd » sur mon" '^[[:space:]]*caps mon = "profile rbd"$' echo "$_m09o_a"
    check_output "ceph-par1 : client.hv-par1 limité au pool hv-par1 sur osd" '^[[:space:]]*caps osd = "profile rbd pool=hv-par1"$' echo "$_m09o_a"
    check_cmd "ceph-par1 : aucune capacité plus large (pas d'« allow * », pas d'autre pool)" bash -c \
      '[[ -n "$1" ]] && ! grep -Eq "allow \*|allow rwx|pool=[^h]|pool=h[^v]" <<<"$1"' _ "$_m09o_a"
  else
    skip "capacités de client.hv-par1" "$_M09O_CEPH ne répond pas"
  fi
else
  echo "  (stockage ceph-par1-rbd absent : contrôle du RANGEMENT)"
  for _m09o_n in $_M09O_NOEUDS; do
    check_ssh "$_m09o_n : plus de trousseau ceph-par1-rbd ni de fichier hv-par1.keyring" "$_m09o_n" \
      '[ ! -e /etc/pve/priv/ceph/ceph-par1-rbd.keyring ] && ! ls /root/*hv-par1* >/dev/null 2>&1'
  done
  check_cmd "plateforme/medisphere : docs/virtualisation/stockage-externe.md sur main" \
    _m09o_fichier_main plateforme/medisphere docs/virtualisation/stockage-externe.md
  if (( _m09o_par1_ok )); then
    _m09o_p="$(_m09o_ceph_par1 'osd pool ls --format json')"
    check_cmd "ceph-par1 répond" _m09o_json "$_m09o_p" 'type == "array"'
    check_cmd "ceph-par1 : le pool hv-par1 n'existe plus" _m09o_json "$_m09o_p" 'index("hv-par1") == null'
    # « auth ls » listerait les clés : on ne lit que les noms d'entités.
    check_cmd "ceph-par1 : l'identité client.hv-par1 n'existe plus" bash -c \
      '[[ -n "$1" ]] && ! grep -qx "client.hv-par1" <<<"$1"' _ "$(_m09o_ceph_par1 "auth ls 2>/dev/null | grep -E '^(client|osd|mgr|mon|mds)\\.'")"
    check_output "ceph-par1 : suppression de pools de nouveau interdite (mon_allow_pool_delete false)" '^false$' \
      _m09o_ceph_par1 'config get mon mon_allow_pool_delete'
  else
    skip "rangement côté ceph-par1" "$_M09O_CEPH arrêtée (normal en fin d'exercice) : pool et identité non vérifiés"
  fi
fi
