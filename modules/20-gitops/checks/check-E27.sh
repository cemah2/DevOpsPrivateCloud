# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E27.sh — M20-E27 « Haute disponibilité et performance d'Argo CD » (PLAT-2127)
# À lancer depuis adm01. Lecture seule : Deployments, StatefulSet, pods, PDB, argocd-cm (wb-checks) ;
# webhooks des projets et leurs événements récents (GitLab, GET) ; documentation sur main.

# shellcheck source=_m20-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-production.sh"

title "M20-E27 — Haute disponibilité et performance d'Argo CD"
require_cmd kubectl jq curl
check_cmd "l'API du cluster répond (readyz)" _m20p_joignable

title "Réplicas et répartition"
_m20_e27_pods="$(_m20p_json -n argocd get pods)"
for _m20_e27_d in argocd-server argocd-repo-server argocd-applicationset-controller; do
  check_cmd "$_m20_e27_d : au moins 2 réplicas prêts" _m20p_jq "$(_m20p_json -n argocd get deployment "$_m20_e27_d")" \
    '(.spec.replicas // 1) >= 2 and (.status.readyReplicas // 0) >= 2'
done
for _m20_e27_d in argocd-server argocd-repo-server; do
  check_cmd "$_m20_e27_d : pods prêts sur au moins deux nœuds" _m20p_jq "$_m20_e27_pods" \
    "[.items[] | select(.metadata.labels[\"app.kubernetes.io/name\"] == \"$_m20_e27_d\" and .status.phase == \"Running\")
      | .spec.nodeName] | unique | length >= 2"
done
_m20_e27_sts="$(_m20p_json -n argocd get statefulset argocd-application-controller)"
check_cmd "contrôleur : StatefulSet à 2 réplicas prêts" _m20p_jq "$_m20_e27_sts" \
  '.spec.replicas == 2 and (.status.readyReplicas // 0) == 2'
check_cmd "contrôleur : ARGOCD_CONTROLLER_REPLICAS = 2 (même nombre que les réplicas)" _m20p_jq "$_m20_e27_sts" \
  'any(.spec.template.spec.containers[0].env[]?; .name == "ARGOCD_CONTROLLER_REPLICAS" and .value == "2")'
_m20_e27_pdb="$(_m20p_json -n argocd get poddisruptionbudgets)"
for _m20_e27_d in argocd-server argocd-repo-server argocd-application-controller argocd-applicationset-controller; do
  check_cmd "une PDB protège $_m20_e27_d" _m20p_jq "$_m20_e27_pdb" \
    "any(.items[]; .spec.selector.matchLabels[\"app.kubernetes.io/name\"] == \"$_m20_e27_d\"
         and (((.spec.minAvailable // 0) | tostring) != \"0\" or .spec.maxUnavailable != null))"
done

title "Réconciliation"
_m20_e27_rec="$(_m20p_cm argocd-cm | jq -r '.data["timeout.reconciliation"] // ""' 2>/dev/null || true)"
_m20_e27_rec_s="$(_m20p_duree_s "$_m20_e27_rec" || true)"
check_output "timeout.reconciliation explicite, 180 s ou plus (valeur : ${_m20_e27_rec:-absente})" '^ok$' \
  bash -c '[[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 180 )) && echo ok' _ "$_m20_e27_rec_s"

title "Webhooks GitLab → Argo CD"
_M20_E27_HOOK="$_M20P_URL/api/webhook"
_m20_e27_webhook() { # PROJET — webhook push, TLS vérifié, réponse 2xx dans les 7 derniers jours
  local id h hid ev
  id="$(_m20p_uri "$1")"
  h="$(gitlab_api "projects/$id/hooks?per_page=100" 2>/dev/null)" || return 1
  hid="$(jq -r --arg u "$_M20_E27_HOOK" '[.[] | select(.url == $u and .push_events == true and .enable_ssl_verification == true)][0].id // empty' \
    <<<"$h" 2>/dev/null)" || return 1
  [[ -n "$hid" ]] || return 1
  ev="$(gitlab_api "projects/$id/hooks/$hid/events?status=successful&per_page=1" 2>/dev/null)" || return 1
  jq -e 'length > 0' >/dev/null 2>&1 <<<"$ev"
}
for _m20_e27_p in plateforme/gitops mediagenda/deploiement; do
  check_cmd "$_m20_e27_p : webhook push vers $_M20_E27_HOOK (TLS vérifié) avec une réponse 2xx récente" \
    _m20_e27_webhook "$_m20_e27_p"
done
_m20_e27_reglages="$(gitlab_api application/settings 2>/dev/null || true)"
if jq -e 'has("outbound_local_requests_whitelist")' >/dev/null 2>&1 <<<"$_m20_e27_reglages"; then
  check_cmd "GitLab : requêtes locales autorisées pour Argo CD seulement (liste, pas d'ouverture générale)" _m20p_jq "$_m20_e27_reglages" \
    '(.allow_local_requests_from_web_hooks_and_services == false)
     and any(.outbound_local_requests_whitelist[]?; test("argocd\\.apps\\.par1\\.medisphere\\.internal|10\\.10\\.41\\.10"))'
else
  skip "liste d'autorisation des requêtes locales de GitLab" "paramètres de l'instance illisibles avec le jeton des checks"
fi

title "Flux et documentation"
check_cmd "matrice des flux de la bordure : git01 → 10.10.41.10:443 (webhooks)" \
  _m20p_doc docs/socle/matrice-flux.md 'webhook' '10\.10\.41\.10'
check_cmd "docs/livraison/gitops/performance.md sur main (mesures, décision Redis)" \
  _m20p_doc docs/livraison/gitops/performance.md 'redis' 'webhook' 'm(e|é)diane'
