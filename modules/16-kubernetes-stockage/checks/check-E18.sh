# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E18.sh — M16-E18 : CloudNativePG : la base de MédiAgenda
# À lancer depuis adm01. Lecture seule : objets Kubernetes (wb-checks, jamais les Secrets), API MédiAgenda publiée en HTTPS (GET).

# shellcheck source=_m16-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-operationnel.sh"

title "M16-E18 — CloudNativePG : la base de MédiAgenda"
require_cmd jq kubectl curl

_m16o_ns=mediagenda-recette
_m16o_url="${WB_MEDIAGENDA_RECETTE_URL:-https://mediagenda-recette.apps.par1.medisphere.internal}"
check_cmd "l'API du cluster répond au compte des vérifications" _m16o_api_repond
_m16o_deps="$(_m16o_kj get deployments -n cnpg-system)"
check_cmd "opérateur CloudNativePG 1.30.1 disponible, image de registry.par1.medisphere.internal" _m16o_json "$_m16o_deps" '
  any(.items[]; (.status.availableReplicas // 0) >= 1
      and any(.spec.template.spec.containers[]; .image | test("^registry\\.par1\\.medisphere\\.internal/.*cloudnative-pg:1\\.30\\.1$")))'
check_cmd "plugin Barman Cloud v0.15.1 disponible, images (plugin et sidecar) de Harbor" _m16o_json "$_m16o_deps" '
  any(.items[]; (.status.availableReplicas // 0) >= 1
      and any(.spec.template.spec.containers[]; .image | test("^registry\\.par1\\.medisphere\\.internal/.*plugin-barman-cloud:v0\\.15\\.1$")))'
check_output "plugin kubectl cnpg installé sur adm01 (1.30.1)" '1\.30\.1' kubectl cnpg version
_m16o_cl="$(_m16o_kj get clusters.postgresql.cnpg.io mediagenda-db -n "$_m16o_ns")"
check_cmd "mediagenda-db : 3 instances prêtes, état sain" _m16o_ready_cnpg "$_m16o_ns" mediagenda-db 3
check_cmd "mediagenda-db : PostgreSQL 18 depuis Harbor, stockage ceph-rbd, réplication synchrone" _m16o_json "$_m16o_cl" '
  .spec.instances == 3 and (.spec.imageName // "" | test("^registry\\.par1\\.medisphere\\.internal/.*postgresql:18"))
  and .spec.storage.storageClass == "ceph-rbd" and ((.spec.postgresql.synchronous.number // 0) >= 1)'
check_cmd "instances sur trois nœuds différents" _m16o_json \
  "$(_m16o_kj get pods -n "$_m16o_ns" -l cnpg.io/cluster=mediagenda-db,cnpg.io/podRole=instance)" \
  '[.items[] | select(.status.phase == "Running") | .spec.nodeName] | length == 3 and (unique | length) == 3'
check_cmd "au moins trois PVC ceph-rbd pour mediagenda-db" \
  _m16o_json "$(_m16o_kj get pvc -n "$_m16o_ns" -l cnpg.io/cluster=mediagenda-db)" \
  '[.items[] | select(.spec.storageClassName == "ceph-rbd" and .status.phase == "Bound")] | length >= 3'
check_cmd "politique d'entrée sur les pods CNPG (cnpg.io/cluster)" \
  _m16o_json "$(_m16o_kj get networkpolicies -n "$_m16o_ns")" \
  'any(.items[]; (.spec.podSelector | tostring | test("cnpg.io/cluster")) and ((.spec.policyTypes // []) | index("Ingress")))'
check_cmd "politique Cilium de sortie vers l'API Kubernetes pour les pods CNPG" \
  _m16o_json "$(_m16o_kj get ciliumnetworkpolicies.cilium.io -n "$_m16o_ns")" \
  'any(.items[]; (.spec.endpointSelector | tostring | test("cnpg.io/cluster")) and any(.spec.egress[]?; (.toEntities // []) | index("kube-apiserver")))'
check_cmd "l'API MédiAgenda lit MEDIAGENDA_DB_URL dans le Secret mediagenda-db-app" \
  _m16o_json "$(_m16o_kj get deployments -n "$_m16o_ns")" '
  any(.items[]; (.status.availableReplicas // 0) >= 1 and any(.spec.template.spec.containers[]; any(.env[]?;
      .name == "MEDIAGENDA_DB_URL" and .valueFrom.secretKeyRef.name == "mediagenda-db-app")))'
check_http "MédiAgenda répond 200 sur /pret (base et cache joignables)" "$_m16o_url/pret" 200
_m16o_rdv() { curl -sf --max-time "$WB_TIMEOUT" "$_m16o_url/api/v1/rendez-vous?limite=100" | jq -e 'length >= 3' >/dev/null; }
check_cmd "au moins trois rendez-vous en base (lus par l'API)" _m16o_rdv
check_cmd "plus de PostgreSQL « jetable » (Deployment ou StatefulSet postgres) dans mediagenda-recette" bash -c '
  jq -e "[.items[] | select(any(.spec.template.spec.containers[]; .image | test(\"postgres\")))] | length == 0" <<<"$1" >/dev/null' \
  _ "$(kube get deployments,statefulsets -n "$_m16o_ns" -o json 2>/dev/null || true)"
check_cmd "journal ~/m16/e18/journal.md rédigé" _m16o_journal E18 8
