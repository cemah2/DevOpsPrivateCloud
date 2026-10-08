#!/usr/bin/env bash
# pool-repliquee.sh — crée ou met en conformité un pool répliqué (M08-E05). Projet plateforme/ceph.
#
# Usage (sur un nœud _admin, en root) :
#   pool-repliquee.sh [--simuler] [--taille N] [--taille-min N] <pool> <application>
#     application : rbd | cephfs | rgw (ou un nom libre)
# Idempotent : un second passage ne change rien. « + » création, « ~ » correction, « = » conforme.
# Ne supprime JAMAIS rien : la suppression d'un pool est un geste manuel et volontaire (M08-E05).
set -euo pipefail

TAILLE=3
TAILLE_MIN=2
SIMULER=0

usage() { sed -n '4,8p' "$0" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --simuler) SIMULER=1; shift ;;
    --taille) TAILLE="${2:?}"; shift 2 ;;
    --taille-min) TAILLE_MIN="${2:?}"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "Option inconnue : $1" >&2; usage ;;
    *) break ;;
  esac
done
[[ $# -eq 2 ]] || usage
POOL="$1"
APPLI="$2"

[[ "$POOL" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || { echo "Nom de pool invalide : $POOL" >&2; exit 2; }
(( TAILLE_MIN >= 1 && TAILLE_MIN <= TAILLE )) || { echo "Il faut 1 <= taille-min <= taille." >&2; exit 2; }
if (( TAILLE_MIN < 2 )); then
  echo "Refus : min_size < 2 accepte d'écrire avec une seule copie (perte de données au moindre incident)." >&2
  exit 2
fi
command -v ceph >/dev/null || { echo "Commande ceph absente (nœud _admin attendu)." >&2; exit 1; }
command -v jq >/dev/null || { echo "jq absent." >&2; exit 1; }

faire() {
  printf '      %s\n' "$*"
  (( SIMULER )) || "$@" >/dev/null
}

detail() {
  ceph osd pool ls detail --format json | jq -c --arg p "$POOL" '.[] | select(.pool_name == $p)'
}

d="$(detail)"
if [[ -z "$d" ]]; then
  echo "+ pool $POOL"
  faire ceph osd pool create "$POOL"
  if (( SIMULER )); then
    d='{"size":0,"min_size":0,"pg_autoscale_mode":"","application_metadata":{}}'
  else
    d="$(detail)"
  fi
else
  echo "= pool $POOL existe"
fi

if [[ "$(jq -r .size <<<"$d")" != "$TAILLE" ]]; then
  echo "~ $POOL size → $TAILLE"
  faire ceph osd pool set "$POOL" size "$TAILLE"
else
  echo "= $POOL size $TAILLE"
fi

if [[ "$(jq -r .min_size <<<"$d")" != "$TAILLE_MIN" ]]; then
  echo "~ $POOL min_size → $TAILLE_MIN"
  faire ceph osd pool set "$POOL" min_size "$TAILLE_MIN"
else
  echo "= $POOL min_size $TAILLE_MIN"
fi

if [[ "$(jq -r .pg_autoscale_mode <<<"$d")" != "on" ]]; then
  echo "~ $POOL pg_autoscale_mode → on"
  faire ceph osd pool set "$POOL" pg_autoscale_mode on
else
  echo "= $POOL autoscaler actif"
fi

if ! jq -e --arg a "$APPLI" '.application_metadata | has($a)' <<<"$d" >/dev/null; then
  echo "~ $POOL application → $APPLI"
  if [[ "$APPLI" == "rbd" ]]; then
    # rbd pool init : marque le pool « rbd » ET crée les objets d'en-tête du pool.
    faire rbd pool init "$POOL"
  else
    faire ceph osd pool application enable "$POOL" "$APPLI"
  fi
else
  echo "= $POOL application $APPLI"
fi
