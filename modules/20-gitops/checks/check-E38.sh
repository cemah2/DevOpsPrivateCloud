# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E38.sh — M20-E38 « Panne : l'application est Degraded après synchronisation » : dev Synced et
# Healthy, pods de l'API prêts et tirés, aucun PVC en attente, sonde /pret, santé des bases CNPG
# cohérente avec leur état réel, RB-200 et journal, panne close. Lecture seule.

# shellcheck source=_m20-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-expert.sh"

title "M20-E38 — MédiAgenda dev redevient Healthy"
require_cmd jq kubectl curl

if ! _m20x_argo_lisible; then
  skip "Applications d'Argo CD" "le compte des checks ne lit pas les Applications (wb-checks-livraison, M20-E03)"
else
  check_cmd "$_m20x_app_dev : Synced, Healthy" _m20x_app_saine "$_m20x_app_dev"
  check_cmd "mediagenda-dev : Deployment mediagenda à jour et disponible" _m20x_deploy_pret "$_m20x_ns_dev" mediagenda
  check_cmd "mediagenda-dev : aucun conteneur en échec de tirage ni pod en attente" \
    _m20x_kq '[.items[] | select(.status.phase == "Pending" or ([.status.containerStatuses[]?.state.waiting.reason // empty] | any(test("ErrImagePull|ImagePullBackOff|CreateContainerConfigError"))))] | length == 0' \
    -n "$_m20x_ns_dev" pods
  for _m20_e38_ns in "$_m20x_ns_dev" "$_m20x_ns_recette" "$_m20x_ns_prod"; do
    check_cmd "$_m20_e38_ns : aucun PVC Pending" _m20x_kq '[.items[] | select(.status.phase == "Pending")] | length == 0' -n "$_m20_e38_ns" pvc
  done
  check_cmd "mediagenda-dev : sonde de disponibilité de l'API sur /pret" \
    _m20x_kq '[.spec.template.spec.containers[] | select(.readinessProbe.httpGet != null) | .readinessProbe.httpGet.path] | length > 0 and all(. == "/pret")' \
    -n "$_m20x_ns_dev" deploy mediagenda
  # Une base CNPG saine (« Cluster in healthy state ») ne doit être déclarée Degraded par aucune Application.
  _m20_e38_sante_coherente() {
    local apps
    apps="$(kube -n "$_m20x_ns" get applications.argoproj.io -o json 2>/dev/null)" || return 1
    for ns in "$_m20x_ns_dev" "$_m20x_ns_recette" "$_m20x_ns_prod"; do
      kube -n "$ns" get clusters.postgresql.cnpg.io -o json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Cluster in healthy state") | "\(.metadata.namespace) \(.metadata.name)"'
    done | while read -r ns nom; do
      jq -e --arg ns "$ns" --arg n "$nom" '[.items[].status.resources[]? | select(.kind == "Cluster" and .namespace == $ns and .name == $n)
        | select((.health.status // "Healthy") != "Healthy")] | length == 0' >/dev/null 2>&1 <<<"$apps" || { echo ko; break; }
    done | grep -q ko && return 1
    return 0
  }
  check_cmd "santé Argo CD des bases CNPG conforme à leur état réel (aucune base saine déclarée Degraded)" _m20_e38_sante_coherente
fi
check_cmd "plateforme/k8s : outil tester-sante.sh présent" _m20x_fichier_present plateforme/k8s tester-sante.sh
check_cmd "RB-200 : section sur l'application Degraded après synchronisation" _m20x_doc_contient "$_m20x_rb200" '^#+ .*Degraded'
check_cmd "journal de diagnostic de INC-4738 commité (docs/kubernetes/journal/)" _m20x_journal 'INC-4738'
check_cmd "panne M20-E38 close (lab/bin/break 20 38 --annuler après réparation)" _m20x_aucune_panne_active E38
