# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E37.sh — M15-E37 « Panne : plus rien ne passe dans l'espace de noms »
#
# Cible : les politiques de mediagenda-recette (refus par défaut + autorisations de M15-E17).
# Variantes :
#   1. CiliumNetworkPolicy « quarantaine » ajoutée : ingressDeny depuis toutes les entités sur tous
#      les pods (le modèle d'isolement d'incident de Sophie, appliqué au mauvais espace) ;
#   2. « étiquette changée » : le sélecteur de pods d'une politique d'autorisation qui vise l'API
#      (NetworkPolicy ou CNP) prend une valeur suffixée « -v2 » : elle ne sélectionne plus rien ;
#   3. le port 5432 (PostgreSQL) des politiques est remplacé par 6432 (« préparation du pooler ») :
#      l'API ne joint plus sa base.
# Cilium applique la politique à chaque paquet non-réponse : les connexions établies tombent aussi.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m15-commun.sh
source "$WB_ROOT/modules/15-kubernetes-reseau/corrige/pannes/_m15-commun.sh"

_E37_CNP=quarantaine

# _e37_etiquettes_api — étiquettes des pods de l'API (JSON), via le sélecteur du Service.
_e37_etiquettes_api() {
  local svc
  svc="$(m15_service_app)"
  [[ -n "$svc" ]] || return 1
  m15_k -n "$_M15_NS_APP" get svc "$svc" -o json 2>/dev/null | jq -c '.spec.selector // {}'
}

# _e37_politiques — lignes « type nom » des politiques de l'espace (NetworkPolicy et CNP).
_e37_politiques() {
  m15_k -n "$_M15_NS_APP" get networkpolicies -o json 2>/dev/null | jq -r '.items[] | "networkpolicy \(.metadata.name)"'
  m15_k -n "$_M15_NS_APP" get ciliumnetworkpolicies -o json 2>/dev/null | jq -r '.items[] | "cnp \(.metadata.name)"'
}

_m15E37_une() {
  local n="$1" t nom j sel vu=0
  case "$n" in
    1)
      m15_sauver cnp "$_E37_CNP" "$_M15_NS_APP"
      m15_k apply -f - >/dev/null 2>&1 <<EOF || return 1
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: $_E37_CNP
  namespace: $_M15_NS_APP
  annotations:
    medisphere.internal/demande: "modèle d'isolement d'incident (SEC-1620)"
spec:
  endpointSelector: {}
  ingressDeny:
    - fromEntities: [all]
EOF
      ;;
    2)
      sel="$(_e37_etiquettes_api)" || return 10
      [[ "$sel" != "{}" && -n "$sel" ]] || return 10
      while read -r t nom; do
        [[ -n "$nom" ]] || continue
        j="$(m15_k -n "$_M15_NS_APP" get "$t" "$nom" -o json 2>/dev/null)" || continue
        # Politique d'autorisation (sélecteur non vide) dont le sélecteur est inclus dans les étiquettes de l'API.
        if jq -e --argjson s "$sel" '
            (.spec.podSelector.matchLabels // .spec.endpointSelector.matchLabels // {}) as $m
            | ($m | length > 0) and ($m | to_entries | all(. as $e | $s[$e.key] == $e.value))' >/dev/null <<<"$j"; then
          if [[ "$t" == networkpolicy ]]; then
            m15_patch_json "$t" "$nom" "$_M15_NS_APP" '.spec.podSelector.matchLabels |= (to_entries | .[0].value += "-v2" | from_entries)' || continue
          else
            m15_patch_json "$t" "$nom" "$_M15_NS_APP" '.spec.endpointSelector.matchLabels |= (to_entries | .[0].value += "-v2" | from_entries)' || continue
          fi
          printf '%s %s\n' "$t" "$nom" >>"$(m15_etat E37)/modifiees"
          vu=1
        fi
      done < <(_e37_politiques)
      ((vu)) || return 10
      ;;
    3)
      while read -r t nom; do
        [[ -n "$nom" ]] || continue
        j="$(m15_k -n "$_M15_NS_APP" get "$t" "$nom" -o json 2>/dev/null)" || continue
        jq -e '[.spec | .. | objects | select(has("port")) | .port | tostring] | index("5432")' >/dev/null <<<"$j" || continue
        m15_patch_json "$t" "$nom" "$_M15_NS_APP" \
          '.spec |= walk(if type == "object" and has("port") and (.port | tostring) == "5432" then .port = (if (.port | type) == "string" then "6432" else 6432 end) else . end)' || continue
        printf '%s %s\n' "$t" "$nom" >>"$(m15_etat E37)/modifiees"
        vu=1
      done < <(_e37_politiques)
      ((vu)) || return 10
      ;;
  esac
  m15_journal E37 "variante $n posée"
}

panne_E37_v1() { m15_preparer && m15_essayer E37 3 1; }
panne_E37_v2() { m15_preparer && m15_essayer E37 3 2; }
panne_E37_v3() { m15_preparer && m15_essayer E37 3 3; }

verifier_E37() { m15_attendre 120 m15_entree_ko; }

annuler_E37() {
  local f t nom j
  m15_k -n "$_M15_NS_APP" delete cnp "$_E37_CNP" --ignore-not-found >/dev/null 2>&1 || true
  f="$(m15_etat E37)/modifiees"
  if [[ -f "$f" ]]; then
    while read -r t nom; do
      j="$(m15_k -n "$_M15_NS_APP" get "$t" "$nom" -o json 2>/dev/null || true)"
      [[ -n "$j" ]] || { m15_remettre "$t" "$nom" "$_M15_NS_APP"; continue; }
      # Marque encore présente : sélecteur suffixé « -v2 » ou port 6432.
      if jq -e '((.spec.podSelector.matchLabels // .spec.endpointSelector.matchLabels // {}) | to_entries | any(.value | endswith("-v2")))
          or ([.spec | .. | objects | select(has("port")) | .port | tostring] | index("6432"))' >/dev/null 2>&1 <<<"$j"; then
        m15_remettre "$t" "$nom" "$_M15_NS_APP"
      fi
    done <"$f"
  fi
  m15_oublier E37
}

resume_E37() {
  echo "Plus rien ne passe vers ou depuis les pods de mediagenda-recette (HTTPS en erreur, API sans base)."
}

symptome_E37() {
  wb_symptome "Ticket INC-4243 — De : Nadia Roussel" \
    "Alerte de la sonde fonctionnelle : https://$_M15_HOTE/pret ne répond plus." \
    "Les pods de $_M15_NS_APP sont Running, mais plus aucun ne reçoit de trafic, ou ils" \
    "n'arrivent plus à parler entre eux, ça dépend de qui regarde. Sophie a « préparé quelque" \
    "chose côté politiques » hier soir avec Lucas, sans ticket de changement." \
    "Interdiction de supprimer la politique de refus par défaut pour « voir si ça repasse »." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 15 37"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 15 E37 3 "$@"; }
fi
