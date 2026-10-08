# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E40.sh — M10-E40 « Panne : les calculs sont down »
#
# Variantes (sur oscmp01 et oscmp02) :
#   1. nova.conf du conteneur nova_compute (/etc/kolla/nova-compute/nova.conf, hors du code) : mot de
#      passe RabbitMQ du transport_url remplacé (« rotation à moitié faite »), nova_compute
#      redémarré → AMQP refusé (ACCESS_REFUSED), plus de compte rendu d'état ;
#   2. table nftables « inet wb_m10_e40 » posée à chaud : sortie vers TCP 5671/5672 rejetée
#      (« durcissement » d'un collègue) → nova-compute perd RabbitMQ ;
#   3. conteneur nova_compute arrêté sur les deux calculs (fin de maintenance oubliée).
# Constat : les deux nova-compute passent « down » dans « openstack compute service list »
# (service_down_time : 60 s par défaut, d'où l'attente).
# Sauvegardes : /var/lib/workbook/M10-E40.* sur les calculs. Rien n'est rétabli qui a déjà été réparé.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m10-commun.sh
source "$WB_ROOT/modules/10-openstack/corrige/pannes/_m10-commun.sh"

_e40_tous_down() {
  local h
  for h in "${_M10_CMP[@]}"; do
    [[ "$(m10_etat_calcul "$h")" == *" down" ]] || return 1
  done
}

_e40_precondition() {
  m10_prerequis || return 1
  if ! m10_calculs_sains; then
    wb_avert "les nova-compute ne sont pas tous « enabled up » avant la panne : lab/bin/check 10 40"
    return 1
  fi
}

_mE40_une() {
  local n="$1" rc=0 h
  for h in "${_M10_CMP[@]}"; do
    m10_exec "$h" VARIANTE="$n" >/dev/null <<'EOF' || rc=$?
case "$VARIANTE" in
  1)
    f=/etc/kolla/nova-compute/nova.conf
    [ -f "$f" ] || exit 10
    neuf="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
    # (?!…) : une ligne déjà modifiée ne correspond plus, la boucle passe à la suivante.
    rx="^(transport_url[ \\t]*=[ \\t]*rabbit://[^:/@]+:)(?!$neuf@)[^@]+@"
    subst "$f" "$rx" "\\g<1>$neuf@" || exit $?
    # Les autres occurrences (plusieurs hôtes RabbitMQ, notifications) : même mot de passe faux.
    while subst "$f" "$rx" "\\g<1>$neuf@"; do :; done
    ctr_redemarrer nova_compute || exit 1
    journal "$f : mot de passe RabbitMQ de transport_url remplacé, nova_compute redémarré"
    ;;
  2)
    command -v nft >/dev/null 2>&1 || exit 10
    nft list table inet wb_m10_e40 >/dev/null 2>&1 && exit 0
    nft -f - <<'NFT' || exit 1
table inet wb_m10_e40 {
  chain sortie {
    type filter hook output priority 0; policy accept;
    tcp dport { 5671, 5672 } counter reject with tcp reset comment "durcissement CHG-1176"
  }
}
NFT
    journal "table nftables inet wb_m10_e40 posée (sortie TCP 5671/5672 rejetée)"
    ;;
  3)
    ctr_arreter nova_compute || exit $?
    ;;
esac
EOF
    ((rc == 0)) || break
  done
  ((rc == 0)) || return "$rc"
  echo "Attente de la détection par Nova (jusqu'à 3 minutes)…"
  if ! m10_attendre 180 _e40_tous_down; then
    _e40_defaire "$n"
    return 10
  fi
}

_e40_defaire() {
  local h
  for h in "${_M10_CMP[@]}"; do
    m10_exec "$h" VARIANTE="$1" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (nova_compute)"
case "$VARIANTE" in
  1)
    if [ -n "$(defaire_subst)" ]; then ctr_redemarrer nova_compute; fi
    ;;
  2)
    if nft list table inet wb_m10_e40 >/dev/null 2>&1; then
      nft delete table inet wb_m10_e40 && journal "annulation : table nftables inet wb_m10_e40 supprimée"
    else
      journal "annulation : table inet wb_m10_e40 déjà retirée (réparation)"
    fi
    ;;
  3)
    ctr_relancer_arretes
    ;;
esac
EOF
  done
}

_e40_injecter() {
  _e40_precondition || return 1
  m10_essayer E40 3 "$1"
}

panne_E40_v1() { _e40_injecter 1; }
panne_E40_v2() { _e40_injecter 2; }
panne_E40_v3() { _e40_injecter 3; }

verifier_E40() { _e40_tous_down; }

annuler_E40() {
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e40_defaire "$WB_VAR" ;;
    *) _e40_defaire 3; _e40_defaire 2; _e40_defaire 1 ;;
  esac
}

resume_E40() {
  echo "Les deux nova-compute (oscmp01, oscmp02) sont « down » : plus aucune instance ne se crée."
}

symptome_E40() {
  wb_symptome "Ticket INC-3746 — De : Nadia Roussel" \
    "La sonde ms-verif-openstack est rouge depuis 6 h 15 : « nova-compute down » sur oscmp01" \
    "et oscmp02. Les instances existantes répondent encore, mais aucune création ni migration" \
    "n'aboutit, et la console d'une instance ne s'ouvre plus. Les deux VMs de calcul sont" \
    "démarrées et répondent en SSH." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 10 40"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 10 E40 3 "$@"; }
fi
