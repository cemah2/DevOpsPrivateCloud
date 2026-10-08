# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E35.sh — M07-E35 « Panne : la session BGP ne monte pas »
#
# Cible : leaf01 (VMID 2073, maquette), côté fabric de la session eBGP leaf01 (AS 65101) ↔ bordure
# gw01/gw02 (AS 65000) sur le VLAN 99 (M07-E16). La bordure n'est JAMAIS modifiée.
# Variantes :
#   1. /etc/frr/frr.conf : « neighbor … remote-as 65000 » devient 65010 (faute de frappe) → OPEN
#      refusé (Bad Peer AS), la session reste en Active/Idle ;
#   2. /etc/frr/frr.conf : la route-map de SORTIE vers la bordure est supprimée ; bgp
#      ebgp-requires-policy étant actif, leaf01 n'annonce plus rien (session Established, « (Policy) ») ;
#   3. /etc/frr/frr.conf : mot de passe TCP-MD5 ajouté côté leaf01 seulement → segments rejetés par
#      les noyaux des deux côtés, la session ne s'établit plus ;
#   4. nftables posé à chaud sur leaf01 (table inet durcissement) : TCP/179 jeté depuis le VLAN 99.
# Constat : gw01 (et gw02 s'il existe) n'a plus aucune route BGP dans 10.10.255.0/24.
# Sauvegardes : /var/lib/workbook/M07-E35.* sur leaf01.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m07-commun.sh
source "$WB_ROOT/modules/07-reseau-ha/corrige/pannes/_m07-commun.sh"

# _e35_bordure_apprend — 0 si au moins une passerelle a une route BGP vers une boucle de la fabric.
_e35_bordure_apprend() {
  local h
  for h in gw01 gw02; do
    m07_existe "$h" || continue
    if remote "$h" "ip -4 route show proto bgp | grep -q '^10\.10\.255\.'" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}
_e35_bordure_muette() { ! _e35_bordure_apprend; }

_e35_precondition() {
  m07_exec leaf01 >/dev/null 2>&1 <<'EOF' || { wb_avert "leaf01 : FRR inactif ou aucune session vers l'AS 65000 dans /etc/frr/frr.conf (lab/bin/check 07 35)"; return 1; }
systemctl is-active -q frr && [ -f /etc/frr/frr.conf ] && grep -Eq '^[[:space:]]*neighbor[[:space:]]+[^[:space:]]+[[:space:]]+remote-as[[:space:]]+65000' /etc/frr/frr.conf
EOF
  if ! _e35_bordure_apprend; then
    wb_avert "la bordure n'apprend déjà aucune route de la fabric : lab/bin/check 07 35 doit être vert avant l'injection"
    return 1
  fi
}

_mE35_une() {
  local n="$1" rc=0
  m07_exec leaf01 N="$n" >/dev/null <<'EOF' || rc=$?
f=/etc/frr/frr.conf
n=0
case "$N" in
  1)
    while subst "$f" '^([ \t]*neighbor[ \t]+\S+[ \t]+remote-as[ \t]+)65000[ \t]*$' '\g<1>65010'; do n=$((n + 1)); done
    [ "$n" -gt 0 ] || exit 10
    journal "$f : remote-as 65000 -> 65010 ($n ligne(s))"
    ;;
  2)
    for nm in $(sed -nE 's/^[ \t]*neighbor[ \t]+([^ \t]+)[ \t]+remote-as[ \t]+65000[ \t]*$/\1/p' "$f"); do
      e="$(printf '%s' "$nm" | sed 's/[.]/\\./g')"
      # Ligne supprimée ; le texte posé garde la ligne précédente et la suivante (contexte unique).
      while subst "$f" "^([^\\n]*\\n)[ \\t]*neighbor[ \\t]+$e[ \\t]+route-map[ \\t]+\\S+[ \\t]+out[ \\t]*\\n([^\\n]*\\n)" '\1\2'; do n=$((n + 1)); done
    done
    [ "$n" -gt 0 ] || exit 10
    journal "$f : route-map de sortie vers la bordure supprimée ($n ligne(s))"
    ;;
  3)
    while subst "$f" '^([ \t]*)neighbor[ \t]+(\S+)[ \t]+remote-as[ \t]+65000[ \t]*$(?!\n[ \t]*neighbor[ \t]+\2[ \t]+password)' '\g<0>\n\1neighbor \2 password Bordure-PAR1-2025'; do n=$((n + 1)); done
    [ "$n" -gt 0 ] || exit 10
    journal "$f : mot de passe TCP-MD5 ajouté côté leaf01 ($n voisin(s))"
    ;;
  4)
    nft_table_poser durcissement '  chain entree {
    type filter hook input priority -10; policy accept;
    ip saddr 10.10.99.0/24 tcp dport 179 counter drop comment "audit SEC : BGP hors fabric"
    ip saddr 10.10.99.0/24 tcp sport 179 counter drop comment "audit SEC : BGP hors fabric"
  }' || exit $?
    journal "nftables : table inet durcissement (TCP/179 depuis 10.10.99.0/24 jeté)"
    ;;
esac
if [ "$N" != 4 ]; then frr_recharger || exit 1; fi
sleep 2
# Session remise à zéro : l'état cassé se voit tout de suite (sinon, selon la variante, il
# n'apparaîtrait qu'à l'expiration du hold time).
for p in $(pairs_bgp 65000 | cut -f1); do vtysh -c "clear bgp $p" >/dev/null 2>&1 || true; done
for p in $(pairs_bgp 65010 | cut -f1); do vtysh -c "clear bgp $p" >/dev/null 2>&1 || true; done
exit 0
EOF
  if ((rc != 0)); then
    _e35_defaire
    return "$rc"
  fi
  if ! m07_attendre 60 _e35_bordure_muette; then
    m07_journal E35 "variante $n posée mais la bordure apprend toujours la fabric"
    _e35_defaire
    return 10
  fi
}

_e35_defaire() {
  m07_annuler_hote leaf01 frr
  m07_exec leaf01 >/dev/null 2>&1 <<'EOF' || true
for p in $(pairs_bgp 65000 | cut -f1); do vtysh -c "clear bgp $p" >/dev/null 2>&1 || true; done
EOF
}

_e35_injecter() {
  _e35_precondition || return 1
  m07_essayer E35 4 "$1"
}

panne_E35_v1() { _e35_injecter 1; }
panne_E35_v2() { _e35_injecter 2; }
panne_E35_v3() { _e35_injecter 3; }
panne_E35_v4() { _e35_injecter 4; }

verifier_E35() { _e35_bordure_muette; }

annuler_E35() { _e35_defaire; }

resume_E35() {
  echo "La bordure (gw01/gw02) n'apprend plus aucune route de la fabric (10.10.255.0/24) : la session BGP avec leaf01 ne sert plus à rien."
}

symptome_E35() {
  wb_symptome "Ticket INC-3401 — De : Karim Benali" \
    "Depuis ce matin, gw01 n'a plus aucune route vers les boucles de la maquette (10.10.255.0/24) :" \
    "« ip route show proto bgp » est vide. Je teste le BGP qui servira à Kubernetes au bloc C, donc" \
    "je veux comprendre, pas seulement que ça remarche. Côté bordure, personne n'a rien changé" \
    "(j'ai vérifié l'historique de plateforme/ansible). InfoGér est intervenu sur la maquette hier." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 07 35"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 07 E35 4 "$@"; }
fi
