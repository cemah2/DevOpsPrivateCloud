#!/usr/bin/env bash
# plateforme/k8s — outils/volumes-orphelins.sh (F1-S07, CHG-3107 ; décision docs/day0/volumes-ancien-cluster.md)
# Volumes RBD du pool k8s-rbd (ceph-par1) qu'aucun PV du cluster actuel n'utilise : ceux de l'ancien
# k8s-par1 (le cluster a disparu avant d'avoir pu supprimer ses PV). Depuis adm01.
#
#   outils/volumes-orphelins.sh lister                       # lecture seule (défaut)
#   outils/volumes-orphelins.sh corbeille <AAAA-MM-JJ>       # met les orphelins dans la CORBEILLE RBD,
#                                                             # purgeable seulement après cette date
# La corbeille est réversible (« rbd trash restore <id> ») jusqu'à la purge ; la purge définitive est
# un geste séparé, décidé par écrit (RB-310 §Après), jamais lancé par cet outil.
# Les sous-volumes CephFS (groupe « csi ») se listent de la même façon (ceph fs subvolume ls) : à
# traiter à part, ils ne sont pas couverts ici.
#
# Variables : CEPH_HOTE (ceph01), POOL (k8s-rbd), KUBECTL_CONTEXTE (k8s-par1).

# shellcheck disable=SC2029  # arguments échappés par printf %q, développés VOLONTAIREMENT côté adm01
set -euo pipefail

CEPH_HOTE="${CEPH_HOTE:-ceph01}"
POOL="${POOL:-k8s-rbd}"
CTX="${KUBECTL_CONTEXTE:-k8s-par1}"
ACTION="${1:-lister}"

# Images utilisées par les PV du cluster actuel (attribut imageName posé par ceph-csi).
utilisees() {
  kubectl --context "$CTX" get pv -o json |
    jq -r '.items[] | select(.spec.csi.driver == "rbd.csi.ceph.com") | .spec.csi.volumeAttributes.imageName // empty' | sort -u
}

# Images csi-vol-* du pool, avec leur taille (octets).
images_pool() {
  ssh "$CEPH_HOTE" "sudo rbd ls -l --format json -p $(printf '%q' "$POOL")" |
    jq -r '.[] | select(.image | startswith("csi-vol-")) | "\(.image)\t\(.size)"' | sort -u
}

# orphelins — images du pool (nom, taille) dont le nom n'est porté par aucun PV actuel.
orphelins() {
  awk -F'\t' 'NR == FNR { u[$1] = 1; next } !($1 in u)' <(utilisees) <(images_pool)
}

case "$ACTION" in
  lister)
    o="$(orphelins || true)"
    n="$(grep -c . <<<"$o" || true)"
    total="$(awk -F'\t' '{ s += $2 } END { printf "%.1f", s / 1024 / 1024 / 1024 }' <<<"$o")"
    printf 'Pool %s : %s image(s) csi-vol-* sans PV dans le cluster actuel, %s Gio provisionnés.\n' "$POOL" "$n" "$total"
    [[ -z "$o" ]] || printf '%s\n' "$o"
    ;;
  corbeille)
    date_purge="${2:?date de purge AAAA-MM-JJ attendue}"
    [[ "$date_purge" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "date invalide : $date_purge" >&2; exit 2; }
    o="$(orphelins | cut -f1)"
    [[ -n "$o" ]] || { echo "Aucun orphelin."; exit 0; }
    printf '%s\n' "$o"
    printf '⚠️  Ces %s image(s) vont dans la corbeille RBD de %s (restaurables jusqu'"'"'au %s). Tape OUI : ' \
      "$(grep -c . <<<"$o")" "$POOL" "$date_purge" >&2
    read -r r
    [[ "$r" == OUI ]] || { echo "Arrêt."; exit 1; }
    while IFS= read -r img; do
      # --expires-at : la corbeille refuse la purge de l'image avant cette date (sauf --force).
      ssh -n "$CEPH_HOTE" "sudo rbd trash mv --expires-at $(printf '%q' "$date_purge") $(printf '%q' "$POOL/$img")"
      echo "corbeille : $img"
    done <<<"$o"
    ;;
  *)
    echo "Usage : $0 lister | corbeille <AAAA-MM-JJ>" >&2
    exit 2
    ;;
esac
