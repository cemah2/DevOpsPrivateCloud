# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E24.sh — M16-E24 « Restaurer un espace de noms complet ailleurs »
# À lancer AVANT le nettoyage de l'étape 8. Lecture seule : espace wb-restauration, objets Restore de
# Velero, Cluster de récupération, charges et PVC de la copie, HTTPRoute et CronJobs restaurés,
# état de la recette, documentation (API GitLab).

# shellcheck source=_m16-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-production.sh"

title "M16-E24 — Restaurer un espace de noms complet ailleurs"
require_cmd jq kubectl curl

_m16_e24_ns="$(_m16p_kj namespace wb-restauration)"
title "Espace cible"
check_cmd "l'espace wb-restauration existe" _m16p_jq "$_m16_e24_ns" '.metadata.name == "wb-restauration"'
check_cmd "wb-restauration : PSA restricted en enforce" \
  _m16p_jq "$_m16_e24_ns" '.metadata.labels["pod-security.kubernetes.io/enforce"] == "restricted"'
check_cmd "wb-restauration : pas de label d'exposition (copie non publiable)" \
  _m16p_jq "$_m16_e24_ns" '(.metadata.labels["medisphere.fr/exposition"] // "non") != "oui"'
check_cmd "plateforme/k8s : wb-restauration décrit sur main" _m16p_recherche_main plateforme/k8s "wb-restauration"

title "Restauration Velero"
_m16_e24_r="$(_m16p_kj restores.velero.io -n velero)"
_m16_e24_filtre='[.items[]? | select(.spec.namespaceMapping["mediagenda-recette"] == "wb-restauration")]'
check_cmd "une restauration remappe mediagenda-recette vers wb-restauration et est Completed" \
  _m16p_jq "$_m16_e24_r" "$_m16_e24_filtre | any(.[]; .status.phase == \"Completed\")"
check_cmd "cette restauration référence une ConfigMap de modificateurs de ressources" \
  _m16p_jq "$_m16_e24_r" "$_m16_e24_filtre | any(.[]; .status.phase == \"Completed\" and (.spec.resourceModifier.kind == \"ConfigMap\") and ((.spec.resourceModifier.name // \"\") | length > 0))"
check_cmd "cette restauration ne recrée pas le Cluster PostgreSQL (exclu ou filtré)" \
  _m16p_jq "$_m16_e24_r" "$_m16_e24_filtre | any(.[]; .status.phase == \"Completed\"
    and ((((.spec.excludedResources // []) | any(test(\"^clusters\\\\.postgresql\\\\.cnpg\\\\.io\$\"))) or ((.spec.labelSelector.matchExpressions // []) | any(.key == \"cnpg.io/cluster\" and .operator == \"DoesNotExist\")))))"

title "Copie : objets"
_m16_e24_routes="$(_m16p_kj httproutes.gateway.networking.k8s.io -n wb-restauration)"
check_cmd "aucune HTTPRoute de la copie ne porte le nom de la recette" \
  _m16p_jq "$_m16_e24_routes" 'all(.items[]?; (.spec.hostnames // []) | all(. != "mediagenda-recette.apps.par1.medisphere.internal"))'
check_cmd "aucune HTTPRoute de la copie n'est acceptée par une Gateway" \
  _m16p_jq "$_m16_e24_routes" 'all(.items[]?; all(.status.parents[]?.conditions[]?; .type != "Accepted" or .status != "True"))'
check_cmd "aucun CronJob actif dans la copie" \
  _m16p_jq "$(_m16p_kj cronjobs -n wb-restauration)" 'all(.items[]?; .spec.suspend == true)'
check_cmd "aucune planification de sauvegarde PostgreSQL dans la copie" \
  _m16p_jq "$(_m16p_kj scheduledbackups.postgresql.cnpg.io -n wb-restauration)" '(.items | length) == 0'

title "Copie : base, volumes, charges"
_m16_e24_cl="$(_m16p_kj clusters.postgresql.cnpg.io mediagenda-db -n wb-restauration)"
check_cmd "wb-restauration/mediagenda-db est sain" _m16p_cluster_sain wb-restauration mediagenda-db
check_cmd "wb-restauration/mediagenda-db démarré par bootstrap.recovery" \
  _m16p_jq "$_m16_e24_cl" '.spec.bootstrap.recovery != null'
check_cmd "wb-restauration/mediagenda-db n'archive rien (aucun plugin isWALArchiver)" \
  _m16p_jq "$_m16_e24_cl" '[.spec.plugins[]? | select(.isWALArchiver == true)] | length == 0'
check_cmd "tous les PVC de la copie sont liés" _m16p_pvc_tous_lies wb-restauration
check_cmd "tous les Deployments et StatefulSets de la copie sont disponibles" _m16p_charges_pretes wb-restauration

title "Recette intacte"
check_cmd "mediagenda-recette/mediagenda-db est sain" _m16p_cluster_sain "$_M16P_RECETTE" "$_M16P_BASE"
check_cmd "mediagenda-recette/mediagenda-db : archivage continu actif" _m16p_archivage_actif "$_M16P_RECETTE" "$_M16P_BASE"
check_cmd "l'API publiée de la recette est prête (/pret)" bash -c '[[ "$1" == 200 ]]' _ "$(_m16p_api_code /pret)"

title "Documentation"
check_cmd "compte rendu tests/restauration-espace-de-noms.md (RTO, wb-restauration)" \
  _m16p_doc_main docs/kubernetes/stockage/tests/restauration-espace-de-noms.md 'wb-restauration' 'RTO'
check_cmd "RB-161 sur main de plateforme/medisphere (docs/kubernetes/stockage)" \
  _m16p_doc_prefixe docs/kubernetes/stockage RB-161 'wb-restauration|namespaceMapping|remapp'
