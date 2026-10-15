# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E35.sh — M15-E35 « Panne : le service ne répond plus »
#
# Cible : le Service de MédiAgenda en recette (premier backendRef de la route « mediagenda »).
# Variantes :
#   1. sélecteur du Service modifié (une valeur suffixée « -v2 ») : EndpointSlice vide ;
#   2. targetPort du Service mis à 8080 (MédiAgenda écoute sur 8000) : points de terminaison
#      présents mais connexion refusée ;
#   3. port du Service changé (80 ↔ 8000) : la route vise un port qui n'existe plus.
# Sauvegarde : le Service (wb_k8s_sauver + JSON). Annulation : seulement si la marque est encore là.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m15-commun.sh
source "$WB_ROOT/modules/15-kubernetes-reseau/corrige/pannes/_m15-commun.sh"

_m15E35_une() {
  local n="$1" svc j filtre
  svc="$(m15_service_app)"
  [[ -n "$svc" ]] || return 1
  j="$(m15_k -n "$_M15_NS_APP" get svc "$svc" -o json 2>/dev/null)" || return 1
  m15_ecrire E35 service "$svc"
  case "$n" in
    1)
      jq -e '.spec.selector | length > 0' >/dev/null <<<"$j" || return 10
      filtre='.spec.selector |= (to_entries | .[0].value += "-v2" | from_entries)'
      ;;
    2)
      [[ "$(jq -r '.spec.ports[0].targetPort' <<<"$j")" != 8080 ]] || return 10
      filtre='.spec.ports[0].targetPort = 8080'
      ;;
    3)
      filtre='.spec.ports[0].port = (if .spec.ports[0].port == 80 then 8000 else 80 end)'
      ;;
  esac
  m15_ecrire E35 avant "$(jq -c '{selector: .spec.selector, ports: .spec.ports}' <<<"$j")"
  m15_patch_json svc "$svc" "$_M15_NS_APP" "$filtre" || return 1
  m15_ecrire E35 pose "$(m15_k -n "$_M15_NS_APP" get svc "$svc" -o json | jq -c '{selector: .spec.selector, ports: .spec.ports}')"
  m15_journal E35 "Service $svc modifié (variante $n)"
}

panne_E35_v1() { m15_preparer && m15_essayer E35 3 1; }
panne_E35_v2() { m15_preparer && m15_essayer E35 3 2; }
panne_E35_v3() { m15_preparer && m15_essayer E35 3 3; }

verifier_E35() { m15_attendre 90 m15_entree_ko; }

annuler_E35() {
  local svc pose actuel
  svc="$(m15_lire E35 service)"
  pose="$(m15_lire E35 pose)"
  if [[ -n "$svc" && -n "$pose" ]]; then
    actuel="$(m15_k -n "$_M15_NS_APP" get svc "$svc" -o json 2>/dev/null | jq -c '{selector: .spec.selector, ports: .spec.ports}' 2>/dev/null || true)"
    if [[ "$actuel" == "$pose" ]]; then
      m15_remettre svc "$svc" "$_M15_NS_APP"
    fi
  fi
  m15_oublier E35
}

resume_E35() {
  echo "MédiAgenda en recette répond par une erreur 5xx (« no healthy upstream » ou équivalent) ; les pods tournent."
}

symptome_E35() {
  wb_symptome "Ticket INC-4241 — De : Julien Petit" \
    "La recette de MédiAgenda est en panne depuis 10 minutes :" \
    "https://$_M15_HOTE/ renvoie une erreur 5xx, alors que les pods sont" \
    "Running et que « kubectl logs » ne montre aucune erreur. Lucas dit avoir « juste fait du" \
    "ménage dans les manifestes » de l'espace $_M15_NS_APP. On a une démonstration client à 15 h." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 15 35"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 15 E35 3 "$@"; }
fi
