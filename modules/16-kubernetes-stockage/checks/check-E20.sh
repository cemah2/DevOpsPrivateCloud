# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E20.sh — M16-E20 : Quotas de stockage et classes par équipe
# À lancer depuis adm01. Lecture seule : objets Kubernetes (wb-checks), API GitLab en GET, journal local.

# shellcheck source=_m16-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-operationnel.sh"

title "M16-E20 — Quotas de stockage et classes par équipe"
require_cmd jq kubectl curl

check_cmd "l'API du cluster répond au compte des vérifications" _m16o_api_repond
# espace total rbd cephfs pvc instantanés min max
for _m16o_l in "mediagenda-dev 10Gi 10Gi 2Gi 10 5 1Gi 5Gi" "mediagenda-recette 40Gi 30Gi 10Gi 20 20 1Gi 10Gi"; do
  read -r _m16o_ns _m16o_t _m16o_r _m16o_f _m16o_p _m16o_s _m16o_min _m16o_max <<<"$_m16o_l"
  check_cmd "$_m16o_ns : quota-stockage (total $_m16o_t, ceph-rbd $_m16o_r, cephfs $_m16o_f, retain 0, $_m16o_p PVC, $_m16o_s instantanés)" \
    _m16o_json "$(_m16o_kj get resourcequota quota-stockage -n "$_m16o_ns")" "$_M16O_JQ_OCTETS"'
    .spec.hard as $h
    | ($h["requests.storage"] | octets) == ($t | octets)
      and ($h["ceph-rbd.storageclass.storage.k8s.io/requests.storage"] | octets) == ($r | octets)
      and ($h["cephfs.storageclass.storage.k8s.io/requests.storage"] | octets) == ($f | octets)
      and ($h["ceph-rbd-retain.storageclass.storage.k8s.io/requests.storage"] | octets) == 0
      and ($h["persistentvolumeclaims"] | tonumber) == ($p | tonumber)
      and ($h["count/volumesnapshots.snapshot.storage.k8s.io"] | tonumber) == ($s | tonumber)' \
    --arg t "$_m16o_t" --arg r "$_m16o_r" --arg f "$_m16o_f" --arg p "$_m16o_p" --arg s "$_m16o_s"
  check_cmd "$_m16o_ns : limites-pvc borne la taille d'un PVC ($_m16o_min à $_m16o_max)" \
    _m16o_json "$(_m16o_kj get limitrange limites-pvc -n "$_m16o_ns")" "$_M16O_JQ_OCTETS"'
    any(.spec.limits[]; .type == "PersistentVolumeClaim" and (.min.storage | octets) == ($a | octets)
        and (.max.storage | octets) == ($b | octets))' --arg a "$_m16o_min" --arg b "$_m16o_max"
  check_cmd "$_m16o_ns : annotation medisphere.internal/classes-stockage = ceph-rbd,cephfs" \
    _m16o_json "$(_m16o_kj get namespace "$_m16o_ns")" \
    '(.metadata.annotations["medisphere.internal/classes-stockage"] // "" | split(",") | map(gsub("^ +| +$"; "")) | sort) == ["ceph-rbd", "cephfs"]'
done
_m16o_vap="$(_m16o_kj get validatingadmissionpolicies.admissionregistration.k8s.io classes-stockage)"
check_cmd "VAP classes-stockage : création de PVC, lit l'annotation de l'espace, sans erreur de typage" _m16o_json "$_m16o_vap" '
  any(.spec.matchConstraints.resourceRules[]; (.resources | index("persistentvolumeclaims")) and ((.operations | index("CREATE")) or (.operations | index("*"))))
  and (tostring | test("namespaceObject")) and (tostring | test("medisphere.internal/classes-stockage"))
  and (((.status.typeChecking.expressionWarnings // []) | length) == 0)'
check_cmd "liaison en Deny sur les espaces étiquetés medisphere.internal/equipe" \
  _m16o_json "$(_m16o_kj get validatingadmissionpolicybindings.admissionregistration.k8s.io)" '
  any(.items[]; .spec.policyName == "classes-stockage" and (.spec.validationActions | index("Deny"))
      and (.spec.matchResources.namespaceSelector | tostring | test("medisphere.internal/equipe")))'
check_cmd "mediagenda-db a toujours 3 instances prêtes" _m16o_ready_cnpg mediagenda-recette mediagenda-db 3
check_cmd "docs/kubernetes/stockage/quotas.md sur main de plateforme/medisphere" \
  _m16o_fichier_main "$_M16O_PROJET_DOC" docs/kubernetes/stockage/quotas.md
check_cmd "journal : tableau des refus (LimitRange, quota, VAP, RBAC)" \
  _m16o_journal_tout E20 8 'LimitRange|limites-pvc' 'quota' 'ValidatingAdmissionPolicy|VAP|classes-stockage' 'forbidden|RBAC'
