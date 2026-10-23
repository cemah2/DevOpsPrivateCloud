#!/usr/bin/env bash
# shellcheck disable=SC2016  # requêtes SQL et awk entre apostrophes
# plateforme/k8s — outils/pra/mesures-pra.sh (F5-S09, INC-6109 ; repris en S12 et S13)
#
# Mesures d'un exercice (ou d'un vrai PRA), en LECTURE SEULE. À lancer sur adm02 pendant le PRA.
#
#   mesures-pra.sh rto                  RTO de chaque nom global : première réponse 2xx servie par par2
#                                       après T0, d'après la sonde ms-sonde-pra
#   mesures-pra.sh rpo                  dernier témoin PRA-TEMOIN présent à PAR2 et écrit AVANT T0 ;
#                                       RPO borné (la valeur exacte se lit à PAR1 au retour, S12)
#   mesures-pra.sh temoins-depuis EPOCH export CSV « id,cree_le,motif » des témoins créés après EPOCH
#                                       (par défaut T0) : preuve de ce qui a été écrit pendant le PRA
#   mesures-pra.sh coupure NOM EPOCH    plus longue suite de mesures non 2xx de NOM après EPOCH (min)
#
# Variables : T0 (secondes ; défaut : /var/lib/workbook/f5-t0), CSV (/var/lib/ms-sonde-pra/mesures.csv),
# KUBECONFIG_PAR2 (~/.kube/k8s-par2.config), NS (mediagenda-prod), CLUSTER (mediagenda-db-par2),
# NOMS (les trois noms globaux).
set -euo pipefail

CSV="${CSV:-/var/lib/ms-sonde-pra/mesures.csv}"
KUBECONFIG_PAR2="${KUBECONFIG_PAR2:-$HOME/.kube/k8s-par2.config}"
NS="${NS:-mediagenda-prod}"
CLUSTER="${CLUSTER:-mediagenda-db-par2}"
NOMS="${NOMS:-mediagenda.medisphere.internal medidoc.medisphere.internal rdv.medisphere.internal}"

lire() { cat "$1" 2>/dev/null || sudo -n cat "$1"; }

t0() {
  if [[ -n "${T0:-}" ]]; then echo "$T0"; return; fi
  lire /var/lib/workbook/f5-t0 | sed -n 's/^T0_EPOCH=\([0-9][0-9]*\)$/\1/p'
}

# CSV avec l'horodatage converti en secondes (GNU date ; lignes illisibles ignorées).
csv_epoch() {
  local l t
  lire "$CSV" | while IFS= read -r l; do
    t="${l%%,*}"
    [[ "$t" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]] || continue
    t="$(date -u -d "$t" +%s 2>/dev/null)" || continue
    printf '%s,%s\n' "$t" "${l#*,}"
  done
}

psql2() {
  local pod
  pod="$(kubectl --kubeconfig "$KUBECONFIG_PAR2" -n "$NS" get cluster "$CLUSTER" -o jsonpath='{.status.currentPrimary}')"
  kubectl --kubeconfig "$KUBECONFIG_PAR2" -n "$NS" exec "$pod" -c postgres -- psql -d mediagenda -AtX -c "$1"
}

cmd_rto() {
  local t nom r
  t="$(t0)"
  [[ -n "$t" ]] || { echo "T0 inconnu" >&2; exit 1; }
  echo "T0 = $(date -d "@$t" '+%F %H:%M:%S %Z')"
  for nom in $NOMS; do
    r="$(csv_epoch | awk -F, -v nom="$nom" -v t0="$t" \
      '$1 >= t0 && index($2, nom) > 0 && $3 ~ /^2[0-9][0-9]$/ && $5 ~ /par2/ { print $1; exit }')"
    if [[ -n "$r" ]]; then
      printf '%-34s reprise %s  RTO %d min\n' "$nom" "$(date -d "@$r" +%H:%M:%S)" $(((r - t + 59) / 60))
    else
      printf '%-34s pas encore servi par par2\n' "$nom"
    fi
  done
}

cmd_rpo() {
  local t dernier e
  t="$(t0)"
  [[ -n "$t" ]] || { echo "T0 inconnu" >&2; exit 1; }
  dernier="$(psql2 "SELECT to_char(max(cree_le) AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')
                    FROM rendez_vous WHERE praticien = 'PRA-TEMOIN' AND cree_le < to_timestamp($t)")"
  [[ -n "$dernier" ]] || { echo "aucun témoin antérieur à T0 à PAR2" >&2; exit 1; }
  e="$(date -d "$dernier" +%s)"
  echo "T0                          : $(date -d "@$t" '+%F %H:%M:%S %Z')"
  echo "dernier témoin à PAR2       : $(date -d "@$e" '+%F %H:%M:%S %Z')"
  echo "RPO (borne haute)           : $(((t - e) / 60)) min $(((t - e) % 60)) s"
  echo "RPO (borne basse, 1 témoin/min jusqu'à T0) : $(((t - e > 60 ? t - e - 60 : 0) / 60)) min"
  echo "Valeur exacte au retour (S12) : dernier témoin écrit à PAR1 avant T0, lu sur l'ancien primaire."
}

cmd_temoins() {
  local depuis="${1:-$(t0)}"
  [[ "$depuis" =~ ^[0-9]+$ ]] || { echo "EPOCH attendu" >&2; exit 1; }
  echo "id,cree_le,motif"
  psql2 "SELECT id || ',' || to_char(cree_le AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') || ',' || coalesce(motif, '')
           FROM rendez_vous WHERE praticien = 'PRA-TEMOIN' AND cree_le >= to_timestamp($depuis) ORDER BY id"
}

cmd_coupure() {
  local nom="${1:?NOM attendu}" depuis="${2:?EPOCH attendu}" r max de a
  r="$(csv_epoch | awk -F, -v nom="$nom" -v t0="$depuis" -v maintenant="$(date +%s)" '
    $1 >= t0 && index($2, nom) > 0 {
      if ($3 ~ /^2[0-9][0-9]$/) { if (debut) { d = $1 - debut; if (d > max) { max = d; de = debut; a = $1 }; debut = 0 } }
      else if (!debut) { debut = $1 }
    }
    END {
      if (debut) { d = maintenant - debut; if (d > max) { max = d; de = debut; a = maintenant } }
      printf "%d %d %d\n", max, de, a
    }')"
  read -r max de a <<<"$r"
  if ((max > 0)); then
    echo "plus longue coupure de $nom : $max s (de $(date -d "@$de" +%H:%M:%S) à $(date -d "@$a" +%H:%M:%S))"
  else
    echo "aucune coupure mesurée pour $nom"
  fi
}

case "${1:-}" in
  rto) cmd_rto ;;
  rpo) cmd_rpo ;;
  temoins-depuis) shift; cmd_temoins "$@" ;;
  coupure) shift; cmd_coupure "$@" ;;
  *) sed -n '5,14p' "$0"; exit 2 ;;
esac
