# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E36.sh — M14-E36 « Panne : des pods restent Pending »
#
# Cible : le témoin « agenda » (wb-pannes) ; une nouvelle version est déployée (« rollout restart ») et
# reste bloquée. Variantes :
#   1. quota de pods de l'espace abaissé au nombre de pods en cours : le nouveau pod n'est même pas
#      créé (FailedCreate « exceeded quota ») ;
#   2. taint de maintenance « maintenance=infoger:NoSchedule » sur tous les travailleurs qui n'en ont
#      pas déjà une : le nouveau pod reste Pending (taint non tolérée) ;
#   3. demande de mémoire de 10 Gi (plus que la mémoire allouable d'un travailleur) : Pending
#      (Insufficient memory) ;
#   4. affinité de nœud obligatoire vers une baie qui n'existe pas (par1-baie-d) : Pending.
# Aucune cause liée au stockage (il arrive au module 16). Annulation : quota, taints et déploiement
# remis comme avant, seulement s'ils portent encore la marque de la panne.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m14-commun.sh
source "$WB_ROOT/modules/14-kubernetes-admin/corrige/pannes/_m14-commun.sh"

_E36_TAINT='maintenance=infoger:NoSchedule'

_e36_quota_bloque() { m14_evenement_depuis E36 "$_M14_NS" FailedCreate 'exceeded quota'; }
_e36_pending() { m14_nouveau_pod_etat E36 agenda "$_M14_JQ_PENDING"; }

_m14E36_une() {
  local n="$1" nb h noeuds=""
  m14_debut E36
  m14_sauver_objet E36 deployment agenda "$_M14_NS"
  case "$n" in
    1)
      m14_sauver_objet E36 resourcequota wb-pannes "$_M14_NS"
      nb="$(m14_pods_json "$_M14_NS" | jq '[.items[] | select(.status.phase != "Succeeded" and .status.phase != "Failed")] | length')" || return 1
      wb_kubectl -n "$_M14_NS" patch resourcequota wb-pannes --type merge \
        -p "{\"metadata\":{\"annotations\":{\"medisphere.internal/ticket\":\"PLAT-1536 (Lucas) : quota resserré\"}},\"spec\":{\"hard\":{\"pods\":\"$nb\"}}}" >/dev/null || return 1
      ;;
    2)
      for h in "${_M14_W[@]}"; do
        if wb_kubectl get node "$h" -o json | jq -e '[.spec.taints[]? | select(.effect == "NoSchedule" or .effect == "NoExecute")] | length == 0' >/dev/null; then
          wb_kubectl taint node "$h" "$_E36_TAINT" >/dev/null || return 1
          noeuds+="$h "
        fi
      done
      [[ -n "$noeuds" ]] || return 10
      m14_ecrire E36 noeuds "$noeuds"
      ;;
    3)
      wb_kubectl -n "$_M14_NS" patch deploy agenda --type strategic -p \
        '{"spec":{"template":{"spec":{"containers":[{"name":"agenda","resources":{"requests":{"memory":"10Gi"},"limits":{"memory":"10Gi"}}}]}}}}' >/dev/null || return 1
      ;;
    4)
      wb_kubectl -n "$_M14_NS" patch deploy agenda --type merge -p \
        '{"spec":{"template":{"spec":{"affinity":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"topology.kubernetes.io/zone","operator":"In","values":["par1-baie-d"]}]}]}}}}}}}' >/dev/null || return 1
      ;;
  esac
  # Variantes 1 et 2 : une « nouvelle version » est déployée ; 3 et 4 en déclenchent une d'elles-mêmes.
  if [[ "$n" == 1 || "$n" == 2 ]]; then
    wb_kubectl -n "$_M14_NS" rollout restart deploy/agenda >/dev/null || return 1
  fi
  m14_journal E36 "variante $n posée ${noeuds:+(taints sur $noeuds)}"
  case "$n" in
    1) m14_attendre 90 _e36_quota_bloque || { _e36_defaire 1; return 10; } ;;
    *) m14_attendre 90 _e36_pending || { _e36_defaire "$n"; return 10; } ;;
  esac
}

_e36_defaire() {
  local n="$1" h q d
  case "$n" in
    1)
      q="$(wb_kubectl -n "$_M14_NS" get resourcequota wb-pannes -o json 2>/dev/null)" || q=""
      if jq -e '.metadata.annotations["medisphere.internal/ticket"] // "" | test("PLAT-1536")' >/dev/null 2>&1 <<<"$q"; then
        m14_restaurer_objet E36 resourcequota wb-pannes "$_M14_NS"
      else
        m14_oublier_objet E36 resourcequota wb-pannes "$_M14_NS"
      fi
      m14_oublier_objet E36 deployment agenda "$_M14_NS"
      ;;
    2)
      for h in $(m14_lire E36 noeuds); do
        if wb_kubectl get node "$h" -o json 2>/dev/null | jq -e '[.spec.taints[]? | select(.key == "maintenance" and .value == "infoger")] | length > 0' >/dev/null 2>&1; then
          wb_kubectl taint node "$h" "${_E36_TAINT}-" >/dev/null 2>&1 || wb_avert "taint non retirée sur $h"
        fi
      done
      m14_oublier E36 noeuds
      m14_oublier_objet E36 deployment agenda "$_M14_NS"
      ;;
    3 | 4)
      d="$(wb_kubectl -n "$_M14_NS" get deploy agenda -o json 2>/dev/null)" || d=""
      if jq -e '.spec.template.spec | (.containers[] | select(.name == "agenda") | .resources.requests.memory == "10Gi")
            or ([.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[]?.matchExpressions[]?.values[]?] | index("par1-baie-d"))' >/dev/null 2>&1 <<<"$d"; then
        m14_restaurer_objet E36 deployment agenda "$_M14_NS"
      else
        m14_oublier_objet E36 deployment agenda "$_M14_NS"
      fi
      ;;
  esac
}

panne_E36_v1() { m14_preparer && m14_essayer E36 4 1; }
panne_E36_v2() { m14_preparer && m14_essayer E36 4 2; }
panne_E36_v3() { m14_preparer && m14_essayer E36 4 3; }
panne_E36_v4() { m14_preparer && m14_essayer E36 4 4; }

verifier_E36() {
  case "$WB_VAR" in
    1) _e36_quota_bloque ;;
    *) _e36_pending ;;
  esac
}

annuler_E36() {
  case "${WB_VAR:-}" in
    [1-4]) _e36_defaire "$WB_VAR" ;;
    *) _e36_defaire 2; _e36_defaire 1; _e36_defaire 3 ;;
  esac
  m14_oublier E36 debut
  m14_journal E36 "annulation"
}

resume_E36() { echo "La nouvelle version de l'agenda de test (wb-pannes) ne se déploie pas : le déploiement reste bloqué."; }

symptome_E36() {
  wb_symptome "Ticket INC-4136 — De : Julien Petit" \
    "Je viens de livrer une nouvelle version de l'agenda de test (déploiement « agenda », espace" \
    "wb-pannes) et le déploiement ne se termine pas : « kubectl rollout status » attend sans fin." \
    "L'ancienne version répond encore, heureusement. Rien n'a changé dans notre code, juré." \
    "Lucas et InfoGér ont tous les deux « fait des réglages » sur le cluster cette semaine." \
    "Débloque la livraison et dis-moi ce qu'il fallait regarder en premier." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 14 36"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 14 E36 4 "$@"; }
fi
