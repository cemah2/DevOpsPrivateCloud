#!/usr/bin/env bash
# k8s-suivre-volume.sh — suit un PVC de k8s-par1 jusqu'à son stockage (lecture seule).
#
# Usage : k8s-suivre-volume.sh [-h] ESPACE PVC
#   Affiche : classe et pilote, PV et volumeHandle, image RBD ou sous-volume CephFS, VolumeAttachment,
#   pods qui utilisent le PVC et leur nœud, chemins attendus sur le nœud, et les commandes à lancer
#   sur le nœud et sur ceph-par1 pour voir le reste. Ne modifie rien.
# Dépendances : kubectl (contexte courant ou KUBECONFIG), jq.
set -euo pipefail

usage() {
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
}

if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then usage; exit 0; fi
if (($# != 2)); then usage >&2; exit 2; fi
for c in kubectl jq; do
  command -v "$c" >/dev/null || { echo "outil manquant : $c" >&2; exit 2; }
done

ns="$1"
pvc="$2"
k() { kubectl --request-timeout=15s "$@"; }

pj="$(k get pvc "$pvc" -n "$ns" -o json)" || { echo "PVC $ns/$pvc introuvable" >&2; exit 1; }
phase="$(jq -r '.status.phase' <<<"$pj")"
classe="$(jq -r '.spec.storageClassName // "(aucune)"' <<<"$pj")"
pv="$(jq -r '.spec.volumeName // empty' <<<"$pj")"
modes="$(jq -r '.spec.accessModes | join(",")' <<<"$pj")"
taille="$(jq -r '.status.capacity.storage // .spec.resources.requests.storage' <<<"$pj")"

printf '== PVC %s/%s\n' "$ns" "$pvc"
printf '   phase %s, classe %s, modes %s, taille %s\n' "$phase" "$classe" "$modes" "$taille"
if [[ "$classe" != "(aucune)" ]]; then
  sc="$(k get storageclass "$classe" -o json 2>/dev/null || true)"
  if [[ -n "$sc" ]]; then
    printf '   StorageClass : pilote %s, rétention %s, liaison %s, extension %s\n' \
      "$(jq -r .provisioner <<<"$sc")" "$(jq -r '.reclaimPolicy // "Delete"' <<<"$sc")" \
      "$(jq -r '.volumeBindingMode // "Immediate"' <<<"$sc")" "$(jq -r '.allowVolumeExpansion // false' <<<"$sc")"
  else
    printf '   StorageClass %s : ABSENTE\n' "$classe"
  fi
fi
if [[ -z "$pv" ]]; then
  echo "   pas encore de PV : voir « kubectl describe pvc $pvc -n $ns » (événements)"
  exit 0
fi

vj="$(k get pv "$pv" -o json)"
pilote="$(jq -r '.spec.csi.driver // "(pas CSI)"' <<<"$vj")"
handle="$(jq -r '.spec.csi.volumeHandle // empty' <<<"$vj")"
printf '\n== PV %s\n' "$pv"
printf '   pilote %s, volumeHandle %s\n' "$pilote" "${handle:-?}"
jq -r '.spec.csi.volumeAttributes // {} | to_entries[] | "   attribut \(.key) = \(.value)"' <<<"$vj"

case "$pilote" in
  rbd.csi.ceph.com)
    pool="$(jq -r '.spec.csi.volumeAttributes.pool // "?"' <<<"$vj")"
    image="$(jq -r '.spec.csi.volumeAttributes.imageName // "?"' <<<"$vj")"
    printf '   image RBD : %s/%s\n' "$pool" "$image"
    printf '   sur ceph01 : sudo rbd info %s/%s ; sudo rbd status %s/%s\n' "$pool" "$image" "$pool" "$image"
    printf '                sudo rados -p %s getomapval csi.volumes.default csi.volume.%s\n' "$pool" "$pv"
    ;;
  cephfs.csi.ceph.com)
    sv="$(jq -r '.spec.csi.volumeAttributes.subvolumeName // "?"' <<<"$vj")"
    fs="$(jq -r '.spec.csi.volumeAttributes.fsName // "?"' <<<"$vj")"
    printf '   sous-volume CephFS : %s (système de fichiers %s)\n' "$sv" "$fs"
    printf '   sur ceph01 : sudo ceph fs subvolume info %s %s --group_name csi\n' "$fs" "$sv"
    ;;
esac

printf '\n== VolumeAttachment\n'
k get volumeattachments -o json | jq -r --arg pv "$pv" '
  [.items[] | select(.spec.source.persistentVolumeName == $pv)]
  | if length == 0 then "   aucun"
    else .[] | "   \(.metadata.name) → nœud \(.spec.nodeName), attaché \(.status.attached // false)\(if .status.attachError then ", erreur : " + .status.attachError.message else "" end)"
    end'

printf '\n== Pods qui utilisent le PVC\n'
pods="$(k get pods -n "$ns" -o json | jq -r --arg c "$pvc" '
  .items[] | select(any(.spec.volumes[]?; .persistentVolumeClaim.claimName == $c))
  | "\(.metadata.name) \(.spec.nodeName // "-") \(.metadata.uid) \(.status.phase)\(if .metadata.deletionTimestamp then "(suppression)" else "" end)"')"
if [[ -z "$pods" ]]; then
  echo "   aucun"
else
  while read -r p n uid ph; do
    printf '   %s sur %s (%s)\n' "$p" "$n" "$ph"
    if [[ "$n" != - && -n "$handle" ]]; then
      empreinte="$(printf '%s' "$handle" | sha256sum | cut -d' ' -f1)"
      printf '     montage global attendu : /var/lib/kubelet/plugins/kubernetes.io/csi/%s/%s/globalmount\n' "$pilote" "$empreinte"
      printf '     montage du pod         : /var/lib/kubelet/pods/%s/volumes/kubernetes.io~csi/%s/mount\n' "$uid" "$pv"
      printf '     sur %s : findmnt -o TARGET,SOURCE,FSTYPE | grep -E "%s|%s"\n' "$n" "$empreinte" "$pv"
    fi
  done <<<"$pods"
fi
