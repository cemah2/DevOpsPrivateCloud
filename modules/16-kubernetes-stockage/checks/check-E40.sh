# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas shell)
# shellcheck source-path=SCRIPTDIR
# check-E40.sh — M16-E40 « Panne : la base PostgreSQL ne bascule plus » : mediagenda-db sain avec
# ses 3 instances, aucune instance clôturée, seuls les PDB de CloudNativePG la couvrent, réplication
# synchrone qui tolère la perte d'une instance, aucun nœud cordonné, et une bascule du primaire a eu lieu depuis l'incident (maintenance faite).

# shellcheck source=_m16-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-expert.sh"

title "M16-E40 — mediagenda-db bascule et la maintenance est faite"
require_cmd kubectl jq

_m16_e40_c="$(_m16x_cnpg)"
check_cmd "mediagenda-db : toutes les instances prêtes (3 au moins)" _m16x_q "$_m16_e40_c" \
  '.spec.instances >= 3 and .status.readyInstances == .spec.instances'
check_cmd "mediagenda-db : phase « Cluster in healthy state »" _m16x_q "$_m16_e40_c" '.status.phase == "Cluster in healthy state"'
check_cmd "mediagenda-db : aucune instance clôturée (fencing)" _m16x_q "$_m16_e40_c" \
  '((.metadata.annotations["cnpg.io/fencedInstances"] // "[]") | fromjson | length) == 0'
check_cmd "les pods de mediagenda-db ne sont couverts que par les PDB de CloudNativePG" _m16x_q \
  "$(_m16x_j pdb -n "$_m16x_ns_db")" \
  'all(.items[] | select((.spec.selector.matchLabels["cnpg.io/cluster"] // "") == "mediagenda-db");
       any(.metadata.ownerReferences[]?; .kind == "Cluster"))'
check_cmd "réplication synchrone : la perte d'une instance ne bloque pas les écritures" _m16x_q "$_m16_e40_c" \
  '(.spec.postgresql.synchronous == null) or ((.spec.postgresql.synchronous.dataDurability // "required") == "preferred")
   or ((.spec.postgresql.synchronous.number // 0) <= (.spec.instances - 2))'
check_cmd "aucun nœud cordonné (maintenance terminée)" _m16x_noeuds_planifiables
_m16_e40_t="$(_m16x_injection E40)"
if ((_m16_e40_t > 0)); then
  check_cmd "le primaire a changé depuis l'incident (bascule faite)" _m16x_q "$_m16_e40_c" \
    '((.status.currentPrimaryTimestamp // "1970-01-01T00:00:00Z") | sub("\\.[0-9]+";"") | fromdateiso8601) >= $t' \
    --argjson t "$_m16_e40_t"
else
  skip "bascule depuis l'incident" "panne jamais injectée"
fi
check_cmd "panne M16-E40 close (lab/bin/break 16 40 --annuler après réparation)" _m16x_aucune_panne_active E40
