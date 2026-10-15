# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E29.sh — M16-E29 « Migrer des données d'une classe de stockage à une autre »
# Lecture seule : StatefulSet valkey, PVC et PV de mediagenda-recette, métadonnées de l'image RBD
# (hôte _admin), sondes de l'API, documentation (API GitLab).

# shellcheck source=_m16-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-production.sh"

title "M16-E29 — Migrer des données d'une classe de stockage à une autre"
require_cmd jq kubectl curl

_m16_e29_sts="$(_m16p_kj statefulset valkey -n "$_M16P_RECETTE")"
_m16_e29_pvc="$(_m16p_kj pvc donnees-valkey-0 -n "$_M16P_RECETTE")"
title "Valkey sur la classe chiffrée"
check_cmd "StatefulSet valkey : volumeClaimTemplates en ceph-rbd-chiffre" \
  _m16p_jq "$_m16_e29_sts" 'all(.spec.volumeClaimTemplates[]; .spec.storageClassName == "ceph-rbd-chiffre")'
check_cmd "StatefulSet valkey prêt" _m16p_jq "$_m16_e29_sts" '(.status.readyReplicas // 0) >= (.spec.replicas // 1)'
check_cmd "PVC donnees-valkey-0 lié, classe ceph-rbd-chiffre" \
  _m16p_jq "$_m16_e29_pvc" '.status.phase == "Bound" and .spec.storageClassName == "ceph-rbd-chiffre"'
_m16_e29_pv="$(jq -r '.spec.volumeName // empty' <<<"$_m16_e29_pvc" 2>/dev/null)" || _m16_e29_pv=""
_m16_e29_img=""
[[ -z "$_m16_e29_pv" ]] || _m16_e29_img="$(_m16p_image_pv "$_m16_e29_pv")" || _m16_e29_img=""
check_cmd "l'image RBD du volume de Valkey est chiffrée (métadonnées ceph-csi)" _m16p_image_chiffree "$_m16_e29_img"
check_cmd "plateforme : le StatefulSet décrit ceph-rbd-chiffre sur main d'un dépôt de MédiAgenda ou de plateforme/k8s" \
  bash -c '[[ "$1" == oui ]]' _ "$( { _m16p_recherche_main mediagenda/deploiement ceph-rbd-chiffre || _m16p_recherche_main plateforme/k8s 'storageClassName: ceph-rbd-chiffre'; } && echo oui || echo non)"

title "Nettoyage"
check_cmd "aucun PVC ni Job de migration dans mediagenda-recette" \
  _m16p_jq "$(_m16p_kj pvc,jobs -n "$_M16P_RECETTE" -l medisphere.fr/migration)" '(.items | length) == 0'
check_cmd "aucun ancien volume de Valkey conservé (PV Released ou Available venant de donnees-valkey-0)" \
  _m16p_jq "$(_m16p_kj pv)" 'all(.items[]; (.status.phase == "Bound") or ((.spec.claimRef.name // "") != "donnees-valkey-0"))'
# Valeur « normale » de failureThreshold des sondes de l'API : celle de M14 (3) ; 6 tolère un réglage
# différent, mais pas la valeur de fenêtre de migration (30) oubliée.
check_cmd "sondes de disponibilité des Deployments de la recette revenues à la normale (failureThreshold ≤ 6)" \
  _m16p_jq "$(_m16p_kj deployments -n "$_M16P_RECETTE")" 'all(.items[].spec.template.spec.containers[]; (.readinessProbe.failureThreshold // 3) <= 6)'

title "Documentation"
check_cmd "compte rendu tests/migration-valkey.md (coupure, clés, témoin)" \
  _m16p_doc_main docs/kubernetes/stockage/tests/migration-valkey.md 'coupure' 'ceph-rbd-chiffre' 'témoin|temoin'
check_cmd "RB-163 sur main de plateforme/medisphere" _m16p_doc_prefixe docs/kubernetes/stockage RB-163 'Retain' 'claimRef'
