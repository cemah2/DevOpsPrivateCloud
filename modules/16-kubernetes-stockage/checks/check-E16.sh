# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E16.sh — M16-E16 : Velero : sauvegarder des espaces de noms
# À lancer depuis adm01. Lecture seule : objets Kubernetes (wb-checks, jamais les Secrets), fichiers locaux, API GitLab en GET.

# shellcheck source=_m16-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-operationnel.sh"

title "M16-E16 — Velero : sauvegarder des espaces de noms"
require_cmd jq kubectl curl

check_cmd "l'API du cluster répond au compte des vérifications" _m16o_api_repond
check_cmd "espace velero en Pod Security « privileged »" _m16o_json "$(_m16o_kj get namespace velero)" \
  '.metadata.labels["pod-security.kubernetes.io/enforce"] == "privileged"'
_m16o_dep="$(_m16o_kj get deployment velero -n velero)"
check_cmd "Velero v1.18.4 disponible, plugin AWS v1.14.4" _m16o_json "$_m16o_dep" '
  (.status.availableReplicas // 0) >= 1
  and any(.spec.template.spec.containers[]; .name == "velero" and (.image | endswith(":v1.18.4")))
  and any(.spec.template.spec.initContainers[]?; .image | test("velero-plugin-for-aws:v1\\.14\\.4$"))'
check_cmd "Velero monte le Secret velero-s3 (identifiants, jamais lus par ce check)" _m16o_json "$_m16o_dep" \
  'any(.spec.template.spec.volumes[]?; .secret.secretName == "velero-s3")'
check_cmd "node-agent prêt sur tous ses nœuds (au moins les trois travailleurs)" \
  _m16o_json "$(_m16o_kj get daemonset node-agent -n velero)" \
  '.status.desiredNumberScheduled >= 3 and .status.numberReady == .status.desiredNumberScheduled'
_m16o_bsl="$(_m16o_kj get backupstoragelocations.velero.io s3-01 -n velero)"
check_cmd "BSL s3-01 disponible et par défaut, vers velero-k8s-par1" _m16o_json "$_m16o_bsl" \
  '.status.phase == "Available" and .spec.default == true and .spec.objectStorage.bucket == "velero-k8s-par1"'
check_cmd "BSL s3-01 : HTTPS vers s3-01:8333, CA fournie, aucune vérification TLS désactivée" _m16o_json "$_m16o_bsl" '
  (.spec.config.s3Url // "") == "https://s3-01.par1.medisphere.internal:8333"
  and (((.spec.objectStorage.caCert // "") != "") or (.spec.objectStorage.caCertRef != null))
  and ((.spec.config.insecureSkipTLSVerify // "false") != "true")'
check_cmd "fichier $HOME/.config/workbook/s3-velero.env en 600" _m16o_local600 "$_M16O_CFG/s3-velero.env"
_m16o_val="$(_m16o_contenu_main "$_M16O_PROJET_K8S" composants/velero/values.yaml)"
check_cmd "composants/velero/values.yaml sur main de plateforme/k8s" test -n "$_m16o_val"
check_cmd "aucune clé dans composants/velero/values.yaml" _m16o_sans_cle "$_m16o_val"
_m16o_bk="$(_m16o_kj get backups.velero.io -n velero)"
check_cmd "une sauvegarde de wb-essais terminée (Completed)" _m16o_json "$_m16o_bk" \
  'any(.items[]; ((.spec.includedNamespaces // []) | index("wb-essais")) != null and .status.phase == "Completed")'
check_cmd "au moins trois restaurations Completed (ou PartiallyFailed)" _m16o_json "$(_m16o_kj get restores.velero.io -n velero)" \
  '[.items[] | select(.status.phase == "Completed" or .status.phase == "PartiallyFailed")] | length >= 3'
_m16o_sch="$(_m16o_kj get schedules.velero.io mediagenda-dev-quotidienne -n velero)"
check_cmd "planification mediagenda-dev-quotidienne : mediagenda-dev, TTL 168 h, fuseau explicite" _m16o_json "$_m16o_sch" '
  (.spec.template.includedNamespaces // []) == ["mediagenda-dev"]
  and (.spec.template.ttl == "168h0m0s" or .spec.template.ttl == "168h")
  and (.spec.schedule | startswith("CRON_TZ="))'
check_cmd "la planification a produit une sauvegarde Completed" _m16o_json "$_m16o_bk" \
  'any(.items[]; .metadata.labels["velero.io/schedule-name"] == "mediagenda-dev-quotidienne" and .status.phase == "Completed")'
check_cmd "journal ~/m16/e16/journal.md rédigé" _m16o_journal E16 10
