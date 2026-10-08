# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E37.sh — M07-E37 « Panne : deux maîtres VRRP »
#
# Paires visées : srv01/srv02 (maquette, VIP 10.10.99.240, VRID 199, M07-E08) et lb01/lb02 (socle,
# VIP 10.10.70.200, VRID 170, M07-E12). Jamais les passerelles gw01/gw02.
# Variantes :
#   1. srv : sur le membre BACKUP, table nftables posée à chaud (inet durcissement) qui jette le
#      protocole VRRP (112) en entrée → il n'entend plus le maître et devient maître à son tour ;
#   2. srv : sur le membre BACKUP, virtual_router_id 199 → 198 dans la configuration de keepalived
#      → chacun est seul dans « son » routeur virtuel, deux maîtres pour la même adresse ;
#   3. lb : sur le MAÎTRE, unicast_peer pointe vers 10.10.70.12 (adresse inexistante) au lieu de
#      l'autre répartiteur → le backup n'entend plus rien et prend la VIP (sans effet si les
#      répartiteurs sont en multicast : variante suivante).
# Constat : la VIP est portée par les deux membres de la paire.
# Sauvegardes : /var/lib/workbook/M07-E37.* sur l'hôte modifié ; hôte et paire notés sur adm01.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m07-commun.sh
source "$WB_ROOT/modules/07-reseau-ha/corrige/pannes/_m07-commun.sh"

declare -A _E37_VIP=([srv]=10.10.99.240 [lb]=10.10.70.200)
declare -A _E37_A=([srv]=srv01 [lb]=lb01)
declare -A _E37_B=([srv]=srv02 [lb]=lb02)
declare -A _E37_IP=([lb01]=10.10.70.10 [lb02]=10.10.70.11)

_e37_paire_de() { case "$1" in 1 | 2) echo srv ;; *) echo lb ;; esac; }

# _e37_maitre PAIRE — affiche le membre qui porte la VIP (rien si aucun ou les deux).
_e37_maitre() {
  local p="$1" a b va=0 vb=0
  a="${_E37_A[$p]}"; b="${_E37_B[$p]}"
  m07_vip_sur "$a" "${_E37_VIP[$p]}" && va=1
  m07_vip_sur "$b" "${_E37_VIP[$p]}" && vb=1
  if ((va == 1 && vb == 0)); then echo "$a"; elif ((va == 0 && vb == 1)); then echo "$b"; fi
}

_e37_deux_maitres() {
  local p="$1"
  m07_vip_sur "${_E37_A[$p]}" "${_E37_VIP[$p]}" && m07_vip_sur "${_E37_B[$p]}" "${_E37_VIP[$p]}"
}

_mE37_une() {
  local n="$1" p maitre cible autre rc=0
  p="$(_e37_paire_de "$n")"
  if [[ "$p" == lb ]] && { ! m07_existe lb01 || ! m07_existe lb02; }; then
    return 10
  fi
  maitre="$(_e37_maitre "$p")"
  if [[ -z "$maitre" ]]; then
    wb_avert "paire ${_E37_A[$p]}/${_E37_B[$p]} : la VIP ${_E37_VIP[$p]} n'est pas portée par un seul membre (lab/bin/check 07 37)"
    return 1
  fi
  if [[ "$maitre" == "${_E37_A[$p]}" ]]; then autre="${_E37_B[$p]}"; else autre="${_E37_A[$p]}"; fi
  if ((n == 3)); then cible="$maitre"; else cible="$autre"; fi
  m07_ecrire E37 cible "$cible"
  m07_ecrire E37 paire "$p"

  m07_exec "$cible" N="$n" PAIR="${_E37_IP[$autre]:-}" >/dev/null <<'EOF' || rc=$?
case "$N" in
  1)
    nft_table_poser durcissement '  chain entree {
    type filter hook input priority -10; policy accept;
    ip protocol vrrp counter drop comment "audit SEC : protocoles non documentes"
  }' || exit $?
    journal "nftables : table inet durcissement (VRRP jeté en entrée)"
    ;;
  2)
    f="$(grep -rlE 'virtual_router_id[[:space:]]+199([^0-9]|$)' /etc/keepalived 2>/dev/null | head -n 1)"
    [ -n "$f" ] || exit 10
    subst "$f" '(virtual_router_id[ \t]+)199\b' '\g<1>198' || exit $?
    keepalived_recharger || exit 1
    journal "$f : virtual_router_id 199 -> 198"
    ;;
  3)
    [ -n "$PAIR" ] || exit 10
    e="$(printf '%s' "$PAIR" | sed 's/[.]/\\./g')"
    f="$(grep -rlE 'unicast_peer' /etc/keepalived 2>/dev/null | head -n 1)"
    [ -n "$f" ] || exit 10
    subst "$f" "(unicast_peer[ \\t]*\\{[^}]*?)$e\\b" '\g<1>10.10.70.12' || exit $?
    keepalived_recharger || exit 1
    journal "$f : unicast_peer $PAIR -> 10.10.70.12"
    ;;
esac
exit 0
EOF
  if ((rc != 0)); then
    _e37_defaire "$cible"
    return "$rc"
  fi
  if ! m07_attendre 30 _e37_deux_maitres "$p"; then
    m07_journal E37 "variante $n posée sur $cible mais un seul maître constaté"
    _e37_defaire "$cible"
    return 10
  fi
}

_e37_defaire() {
  local h="${1:-}"
  if [[ -n "$h" ]]; then
    m07_annuler_hote "$h" keepalived
    return 0
  fi
  for h in srv01 srv02 lb01 lb02; do
    if m07_maquette "$h" || m07_existe "$h"; then m07_annuler_hote "$h" keepalived; fi
  done
}

_e37_injecter() { m07_essayer E37 3 "$1"; }

panne_E37_v1() { _e37_injecter 1; }
panne_E37_v2() { _e37_injecter 2; }
panne_E37_v3() { _e37_injecter 3; }

verifier_E37() { _e37_deux_maitres "$(m07_lire E37 paire)"; }

annuler_E37() { _e37_defaire "$(m07_lire E37 cible)"; }

resume_E37() {
  if [[ "$(m07_lire E37 paire)" == lb ]]; then
    echo "La VIP des répartiteurs (10.10.70.200) est vue sur lb01 ET lb02 ; erreurs de connexion intermittentes vers GitLab et NetBox."
  else
    echo "La VIP de démonstration 10.10.99.240 est portée à la fois par srv01 et srv02."
  fi
}

symptome_E37() {
  local detail
  if [[ "$(m07_lire E37 paire)" == lb ]]; then
    detail="La sonde VRRP voit la VIP 10.10.70.200 (lb.par1.medisphere.internal) sur lb01 ET sur lb02. Les développeurs ont des erreurs de connexion intermittentes vers GitLab."
  else
    detail="La sonde VRRP voit la VIP 10.10.99.240 sur srv01 ET sur srv02. La page servie par la VIP change de serveur d'une minute à l'autre."
  fi
  wb_symptome "Ticket INC-3403 — De : Nadia Roussel" \
    "Alerte de la supervision cette nuit : « deux maîtres VRRP »." \
    "$detail" \
    "Rien n'a été déployé par le pipeline depuis hier. Rétablis un seul maître, et explique-moi" \
    "pourquoi keepalived n'a rien dit." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 07 37"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 07 E37 3 "$@"; }
fi
