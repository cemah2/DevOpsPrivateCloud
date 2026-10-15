# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes ou bash -c entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E36.sh — M14-E36 « Panne : des pods restent Pending » : le témoin agenda est entièrement
# déployé, aucun pod Pending dans les espaces du workbook, quota avec de la marge, travailleurs
# ordonnançables, demandes de ressources raisonnables, RB-144 (section Pending), panne close.
# Lecture seule.

# shellcheck source=_m14-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-expert.sh"

title "M14-E36 — Plus aucun pod Pending"
require_cmd jq kubectl

if ! _m14x_api_repond; then
  skip "pods et ordonnancement" "l'API ne répond pas au compte des checks (lab/bin/check 14 39)"
elif ! _m14x_temoins; then
  skip "témoins de wb-pannes" "absents : ils sont créés à la première injection (lab/bin/break 14 36)"
else
  check_cmd "déploiement agenda (wb-pannes) entièrement à jour et disponible" _m14x_deploy_pret "$_m14x_ns" agenda
  _m14_e36_pending() {
    local ns
    for ns in $(_m14x_espaces_workbook); do
      kube -n "$ns" get pods -o json 2>/dev/null | jq -e '
        [.items[] | select(.status.phase == "Pending")
                  | select((now - (.metadata.creationTimestamp | fromdateiso8601)) > 120)] | length == 0' >/dev/null 2>&1 || return 1
    done
  }
  check_cmd "aucun pod Pending depuis plus de 2 min dans les espaces wb-* et mediagenda-*" _m14_e36_pending
  check_cmd "quota de wb-pannes : au moins 2 pods de marge, aucune ressource saturée" \
    _m14x_kq '.status as $s | (($s.hard.pods | tonumber) - ($s.used.pods | tonumber)) >= 2
              and all($s.hard | keys[]; . as $k | ($s.used[$k] // "0") != $s.hard[$k])' -n "$_m14x_ns" resourcequota wb-pannes
  check_cmd "aucune taint « maintenance » sur les nœuds" \
    _m14x_kq '[.items[].spec.taints[]? | select(.key == "maintenance")] | length == 0' nodes
  check_cmd "au moins deux travailleurs acceptent des pods sans tolérance particulière" \
    _m14x_kq '[.items[] | select(.metadata.name | test("^k8s-w"))
               | select([.spec.taints[]? | select(.effect == "NoSchedule" or .effect == "NoExecute")] | length == 0)] | length >= 2' nodes
  _m14_e36_demande() {
    local q
    q="$(kube -n "$_m14x_ns" get deploy agenda -o json 2>/dev/null | jq -r '.spec.template.spec.containers[] | select(.name == "agenda") | .resources.requests.memory // "0"')"
    (($(_m14x_memoire_mio "$q") <= 1024))
  }
  check_cmd "agenda : demande de mémoire d'au plus 1 Gi" _m14_e36_demande
  check_cmd "agenda : aucune affinité obligatoire vers une baie qui n'existe pas" \
    _m14x_kq '[.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[]?.matchExpressions[]?.values[]?] | index("par1-baie-d") | not' \
    -n "$_m14x_ns" deploy agenda
fi
check_cmd "RB-144 (un pod ne démarre pas) publié, avec une section sur les pods Pending" \
  _m14x_doc_contient 'docs/kubernetes/runbooks/RB-144-*.md' '^#+ .*Pending'
check_cmd "panne M14-E36 close (lab/bin/break 14 36 --annuler après réparation)" _m14x_aucune_panne_active E36
