# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E42.sh — M16-E42 « Panne : le snapshot ne se termine jamais »
#
# Après l'injection, la panne demande un instantané du témoin temoin-rbd (VolumeSnapshot
# temoin-rbd-HHMM, classe ceph-rbd-snap, espace wb-essais), qui ne devient jamais prêt. Variantes :
#   1. contrôleur arrêté : Deployment kube-system/snapshot-controller à 0 réplique ;
#   2. VolumeSnapshotClass fausse : ceph-rbd-snap recréée avec un espace de noms de Secret de
#      snapshotter erroné (« ceph-csi-rbd » au lieu de celui de la StorageClass) ;
#   3. contrôleur privé de droits : le ClusterRoleBinding qui donne ses droits au compte de service
#      kube-system/snapshot-controller est supprimé, puis les pods du contrôleur redémarrés.
# La CRD n'est jamais touchée (sa suppression effacerait tous les instantanés existants).
# Sauvegardes : Deployment, VolumeSnapshotClass, ClusterRoleBinding (wb_k8s_sauver). L'annulation
# rétablit d'abord le contrôleur, puis supprime l'instantané de test s'il n'est toujours pas prêt
# (prêt, il reste : c'est la preuve de la réparation, lue par check-E42).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m16-commun.sh
source "$WB_ROOT/modules/16-kubernetes-stockage/corrige/pannes/_m16-commun.sh"

_E42_CTRL=snapshot-controller

# _e42_crb — ClusterRoleBindings qui lient le compte de service du contrôleur.
_e42_crb() {
  m16_k get clusterrolebindings -o json | jq -r --arg sa "$_E42_CTRL" '
    .items[] | select(any(.subjects[]?; .kind == "ServiceAccount" and .name == $sa and .namespace == "kube-system"))
    | .metadata.name'
}

_e42_sans_controleur() {
  [[ -z "$(m16_k get pods -n kube-system -l app.kubernetes.io/name=snapshot-controller -o name)" ]]
}

_e42_vs() { m16_lire E42 instantane; }

_m16E42_une() {
  local n="$1" nb j c
  case "$n" in
    1)
      nb="$(m16_k get deployment "$_E42_CTRL" -n kube-system -o jsonpath='{.spec.replicas}')"
      [[ "${nb:-0}" =~ ^[1-9][0-9]*$ ]] || return 10
      m16_ecrire E42 repliques "$nb"
      wb_kubectl scale deployment "$_E42_CTRL" -n kube-system --replicas=0 >/dev/null 2>&1 || return 1
      m16_attendre 90 _e42_sans_controleur || true
      ;;
    2)
      j="$(m16_json volumesnapshotclass "$_M16_VSC_RBD")"
      [[ -n "$j" ]] || return 10
      [[ -n "$(jq -r '.parameters["csi.storage.k8s.io/snapshotter-secret-namespace"] // empty' <<<"$j")" ]] || return 10
      m16_sauver volumesnapshotclass "$_M16_VSC_RBD"
      j="$(jq -c 'del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.managedFields,
                      .metadata.generation, .metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"])
                  | .parameters["csi.storage.k8s.io/snapshotter-secret-namespace"] = "ceph-csi-rbd"' <<<"$j")"
      wb_kubectl delete volumesnapshotclass "$_M16_VSC_RBD" --wait=true >/dev/null 2>&1 || return 1
      wb_kubectl create -f - <<<"$j" >/dev/null 2>&1 || { _e42_defaire 2; return 1; }
      m16_ecrire E42 classe oui
      ;;
    3)
      c="$(_e42_crb)"
      [[ -n "$c" ]] || return 10
      local b
      for b in $c; do m16_sauver clusterrolebinding "$b"; done
      m16_ecrire E42 crb "$(tr '\n' ' ' <<<"$c")"
      for b in $c; do wb_kubectl delete clusterrolebinding "$b" >/dev/null 2>&1 || true; done
      wb_kubectl delete pods -n kube-system -l app.kubernetes.io/name=snapshot-controller --wait=false >/dev/null 2>&1 || true
      sleep 20
      ;;
  esac
  m16_ecrire E42 posee "$n"
  m16_journal E42 "variante $n posée"
}

_e42_defaire() {
  local nb b
  case "$1" in
    1)
      nb="$(m16_lire E42 repliques)"
      [[ -n "$nb" ]] || return 0
      if [[ "$(m16_k get deployment "$_E42_CTRL" -n kube-system -o jsonpath='{.spec.replicas}')" == 0 ]]; then
        wb_kubectl scale deployment "$_E42_CTRL" -n kube-system --replicas="$nb" >/dev/null 2>&1 \
          || wb_avert "annulation : snapshot-controller non relancé"
      fi ;;
    2)
      [[ "$(m16_lire E42 classe)" == oui ]] || return 0
      if [[ "$(m16_k get volumesnapshotclass "$_M16_VSC_RBD" -o jsonpath='{.parameters.csi\.storage\.k8s\.io/snapshotter-secret-namespace}')" == ceph-csi-rbd ]] \
        || ! m16_existe volumesnapshotclass "$_M16_VSC_RBD"; then
        wb_kubectl delete volumesnapshotclass "$_M16_VSC_RBD" --ignore-not-found --wait=true >/dev/null 2>&1 || true
        m16_restaurer volumesnapshotclass "$_M16_VSC_RBD"
      else
        rm -f -- "$(_m16_fichier volumesnapshotclass "$_M16_VSC_RBD")"
      fi ;;
    3)
      for b in $(m16_lire E42 crb); do
        if m16_existe clusterrolebinding "$b"; then
          rm -f -- "$(_m16_fichier clusterrolebinding "$b")"
        else
          m16_restaurer clusterrolebinding "$b"
        fi
      done
      wb_kubectl delete pods -n kube-system -l app.kubernetes.io/name=snapshot-controller --wait=false >/dev/null 2>&1 || true ;;
  esac
}

_e42_injecter() {
  local nom
  m16_preparer || return 1
  m16_pret kube-system "$_E42_CTRL" || { wb_avert "snapshot-controller pas disponible avant la panne (M16-E06)"; return 1; }
  m16_existe volumesnapshotclass "$_M16_VSC_RBD" || { wb_avert "VolumeSnapshotClass $_M16_VSC_RBD absente (M16-E10)"; return 1; }
  m16_horodater E42
  m16_essayer E42 3 "$1" || return 1
  nom="temoin-rbd-$(date +%H%M)"
  m16_ecrire E42 instantane "$nom"
  wb_kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $nom
  namespace: $_M16_NS_T
  labels: {app.kubernetes.io/name: temoin-rbd, medisphere.internal/temoin: m16}
spec:
  volumeSnapshotClassName: $_M16_VSC_RBD
  source: {persistentVolumeClaimName: temoin-rbd}
EOF
}

panne_E42_v1() { _e42_injecter 1; }
panne_E42_v2() { _e42_injecter 2; }
panne_E42_v3() { _e42_injecter 3; }

verifier_E42() {
  sleep 60
  [[ "$(m16_k get volumesnapshot "$(_e42_vs)" -n "$_M16_NS_T" -o jsonpath='{.status.readyToUse}')" != true ]]
}

annuler_E42() {
  local vs
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e42_defaire "$WB_VAR" ;;
    *) _e42_defaire 3; _e42_defaire 2; _e42_defaire 1 ;;
  esac
  vs="$(_e42_vs)"
  # Un instantané devenu prêt est la preuve de la réparation (lue par le contrôle) : il reste ;
  # seul un instantané encore bloqué est supprimé.
  if [[ -n "$vs" && "$(m16_k get volumesnapshot "$vs" -n "$_M16_NS_T" -o jsonpath='{.status.readyToUse}')" != true ]]; then
    sleep 30
  fi
  if [[ -n "$vs" && "$(m16_k get volumesnapshot "$vs" -n "$_M16_NS_T" -o jsonpath='{.status.readyToUse}')" != true ]]; then
    wb_kubectl delete volumesnapshot "$vs" -n "$_M16_NS_T" --ignore-not-found --wait=true --timeout=90s >/dev/null 2>&1 \
      || wb_avert "annulation : instantané $vs non supprimé (finaliseur ?) : à supprimer quand le contrôleur sera revenu"
  fi
  m16_journal E42 "annulation"
  m16_effacer_etat E42
}

resume_E42() {
  echo "L'instantané $(_e42_vs) du témoin temoin-rbd (wb-essais) ne devient jamais prêt."
}

symptome_E42() {
  wb_symptome "Ticket INC-4348 — De : Karim Benali" \
    "J'ai demandé un instantané du volume témoin (VolumeSnapshot $(_e42_vs), espace wb-essais) avant" \
    "un essai : vingt minutes plus tard, READYTOUSE n'est toujours pas à true. Les sauvegardes Velero" \
    "qui déplacent les données de snapshots CSI vont toutes rester bloquées pareil. Tout allait bien" \
    "avant la « mise au propre » des composants de kube-system par Lucas." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 16 42"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 16 E42 3 "$@"; }
fi
