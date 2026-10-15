# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E22.sh — M17-E22 « Panne : conflit de propriété des champs »
#
# Cible : release Helm « mediagenda » de mediagenda-dev (Helm 4, server-side apply, gestionnaire helm).
# Variantes (chacune prend la propriété d'un champ que le chart rend, avec une autre valeur) :
#   1. « kubectl edit » simulé (patch avec --field-manager=kubectl-edit, opération Update) sur le
#      Deployment : MEDIAGENDA_LOG_LEVEL=DEBUG et limite mémoire de l'API relevée ;
#   2. « kubectl apply » côté client (gestionnaire kubectl-client-side-apply, annotation
#      last-applied-configuration) d'une copie modifiée de la ConfigMap : MEDIAGENDA_CACHE_TTL=5 ;
#   3. un HorizontalPodAutoscaler « mediagenda » (min 2, max 3) : le contrôleur porte spec.replicas à 2
#      par la sous-ressource scale (gestionnaire kube-controller-manager).
# Tout « helm upgrade » de la release échoue ensuite en conflit, même à valeurs inchangées.
# Annulation (seulement si c'est encore cassé) : suppression du HPA posé (même UID), retrait des
# entrées managedFields injectées, puis « helm rollback » vers la révision courante avec
# --force-conflicts : Helm repose et reprend ses valeurs.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m17-commun.sh
source "$WB_ROOT/modules/17-packaging/corrige/pannes/_m17-commun.sh"

_E22_NS=mediagenda-dev
_E22_REL=mediagenda

_e22_mf() { # _e22_mf TYPE NOM — managedFields en JSON
  wb_kubectl get "$1" "$2" -n "$_E22_NS" --show-managed-fields -o json 2>/dev/null | jq -c '.metadata.managedFields // []' 2>/dev/null
}

# _e22_retirer_gestionnaire TYPE NOM GESTIONNAIRE [SOUS-RESSOURCE] — supprime l'entrée managedFields.
_e22_retirer_gestionnaire() {
  local t="$1" n="$2" g="$3" sr="${4:-}" mf idx
  mf="$(_e22_mf "$t" "$n")"
  idx="$(jq --arg g "$g" --arg sr "$sr" '[to_entries[] | select(.value.manager == $g and ((.value.subresource // "") == $sr)) | .key] | first // empty' <<<"$mf" 2>/dev/null)" || idx=""
  [[ -n "$idx" ]] || return 0
  wb_kubectl patch "$t" "$n" -n "$_E22_NS" --type json -p "[{\"op\":\"remove\",\"path\":\"/metadata/managedFields/$idx\"}]" >/dev/null 2>&1 || true
}

_e22_a() { # _e22_a TYPE NOM GESTIONNAIRE [SOUS-RESSOURCE] — 0 si le gestionnaire est présent
  _e22_mf "$1" "$2" | jq -e --arg g "$3" --arg sr "${4:-}" 'any(.[]; .manager == $g and ((.subresource // "") == $sr))' >/dev/null 2>&1
}

_mE22_une() {
  local v="$1" cm hpa n
  case "$v" in
    1)
      wb_k8s_sauver deployment "$_E22_REL" "$_E22_NS"
      wb_kubectl patch deployment "$_E22_REL" -n "$_E22_NS" --field-manager=kubectl-edit --type strategic -p '
spec:
  template:
    spec:
      containers:
        - name: api
          env:
            - name: MEDIAGENDA_LOG_LEVEL
              value: DEBUG
          resources:
            limits:
              memory: 1Gi' >/dev/null || return 1
      ;;
    2)
      wb_kubectl get configmap "$_E22_REL" -n "$_E22_NS" >/dev/null 2>&1 || return 10
      wb_k8s_sauver configmap "$_E22_REL" "$_E22_NS"
      cm="$(wb_kubectl get configmap "$_E22_REL" -n "$_E22_NS" -o json | jq -c '
          {apiVersion, kind, metadata: {name: .metadata.name, namespace: .metadata.namespace,
            labels: .metadata.labels, annotations: (.metadata.annotations // {} | with_entries(select(.key | startswith("meta.helm.sh/"))))},
           data: (.data + {MEDIAGENDA_CACHE_TTL: "5"})}')" || return 1
      [[ "$(jq -r '.data.MEDIAGENDA_CACHE_TTL' <<<"$cm")" == 5 ]] || return 10
      printf '%s\n' "$cm" | wb_kubectl apply -f - >/dev/null 2>&1 || return 1
      ;;
    3)
      wb_kubectl get hpa "$_E22_REL" -n "$_E22_NS" >/dev/null 2>&1 && return 10
      n="$(wb_kubectl get deployment "$_E22_REL" -n "$_E22_NS" -o jsonpath='{.spec.replicas}')" || return 1
      ((n < 2)) || return 10
      wb_k8s_sauver horizontalpodautoscaler "$_E22_REL" "$_E22_NS"
      wb_kubectl apply -f - >/dev/null <<EOF || return 1
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ${_E22_REL}
  namespace: ${_E22_NS}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ${_E22_REL}
  minReplicas: 2
  maxReplicas: 3
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 80
EOF
      hpa="$(wb_kubectl get hpa "$_E22_REL" -n "$_E22_NS" -o jsonpath='{.metadata.uid}')" || hpa=""
      m17_ecrire E22 hpa "$hpa"
      # Le contrôleur HPA agit à sa période de synchronisation (15 s par défaut).
      for _ in $(seq 1 20); do
        [[ "$(wb_kubectl get deployment "$_E22_REL" -n "$_E22_NS" -o jsonpath='{.spec.replicas}' 2>/dev/null)" -ge 2 ]] 2>/dev/null && break
        sleep 5
      done
      ;;
  esac
  m17_ecrire E22 variante "$v"
  m17_journal E22 "variante $v posée sur $_E22_NS/$_E22_REL"
}

_e22_injecter() {
  m17_outils kubectl helm jq || return 1
  m17_rel_saine "$_E22_NS" "$_E22_REL" || { wb_avert "la release $_E22_REL de $_E22_NS doit être « deployed » (banc d'essai du chart, M17-E03)"; return 1; }
  m17_rel_ssa "$_E22_NS" "$_E22_REL" || { wb_avert "la release $_E22_REL n'est pas en server-side apply : réinstalle-la avec Helm 4 (M17-E14)"; return 1; }
  m17_essayer E22 3 "$1"
}

panne_E22_v1() { _e22_injecter 1; }
panne_E22_v2() { _e22_injecter 2; }
panne_E22_v3() { _e22_injecter 3; }

verifier_E22() {
  case "${WB_VAR:-}" in
    1) _e22_a deployment "$_E22_REL" kubectl-edit ;;
    2) _e22_a configmap "$_E22_REL" kubectl-client-side-apply ;;
    3) [[ "$(wb_kubectl get deployment "$_E22_REL" -n "$_E22_NS" -o jsonpath='{.spec.replicas}' 2>/dev/null)" -ge 2 ]] 2>/dev/null \
         && _e22_a deployment "$_E22_REL" kube-controller-manager scale ;;
    *) return 1 ;;
  esac
}

annuler_E22() {
  local v hpa uid rev a_rejouer=0
  v="$(m17_lire E22 variante)"
  case "${v:-${WB_VAR:-}}" in
    1)
      if _e22_a deployment "$_E22_REL" kubectl-edit; then
        _e22_retirer_gestionnaire deployment "$_E22_REL" kubectl-edit
        a_rejouer=1
      fi
      ;;
    2)
      if _e22_a configmap "$_E22_REL" kubectl-client-side-apply; then
        _e22_retirer_gestionnaire configmap "$_E22_REL" kubectl-client-side-apply
        wb_kubectl annotate configmap "$_E22_REL" -n "$_E22_NS" kubectl.kubernetes.io/last-applied-configuration- >/dev/null 2>&1 || true
        a_rejouer=1
      fi
      ;;
    3)
      hpa="$(m17_lire E22 hpa)"
      uid="$(wb_kubectl get hpa "$_E22_REL" -n "$_E22_NS" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"
      if [[ -n "$hpa" && "$uid" == "$hpa" ]]; then
        wb_kubectl delete hpa "$_E22_REL" -n "$_E22_NS" >/dev/null 2>&1 || wb_avert "annulation : HPA non supprimé"
        if _e22_a deployment "$_E22_REL" kube-controller-manager scale; then
          _e22_retirer_gestionnaire deployment "$_E22_REL" kube-controller-manager scale
          a_rejouer=1
        fi
      fi
      ;;
  esac
  if ((a_rejouer)) && [[ "$(m17_rel_statut "$_E22_NS" "$_E22_REL")" == deployed ]]; then
    rev="$(m17_helm status "$_E22_REL" -n "$_E22_NS" -o json 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true)"
    if [[ -n "$rev" ]]; then
      m17_helm rollback "$_E22_REL" "$rev" -n "$_E22_NS" --force-conflicts --no-hooks >/dev/null 2>&1 \
        || wb_avert "annulation : « helm rollback $_E22_REL $rev » a échoué, relance-le à la main"
    fi
  fi
  m17_journal E22 "annulation (variante ${v:-?})"
  rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/k8s/$WB_EX"
  m17_oublier E22 variante
  m17_oublier E22 hpa
}

resume_E22() { echo "Le « helm upgrade » du dev échoue en conflit, même sans changer de valeur."; }

symptome_E22() {
  wb_symptome "Ticket INC-4422 — De : Julien Petit" \
    "Depuis ce matin, « helm upgrade mediagenda … -n mediagenda-dev » échoue, même quand je reprends" \
    "exactement les valeurs actuelles (helm get values) et la même version du chart. Hier tout marchait." \
    "Lucas jure qu'il n'a « rien cassé, juste regardé » le dev. Je voudrais monter le dev sans" \
    "« --force-quelque-chose » dont je ne comprends pas l'effet." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 17 22"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 17 E22 3 "$@"; }
fi
