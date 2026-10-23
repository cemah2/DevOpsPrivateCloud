#!/usr/bin/env bash
# plateforme/resilience — outils/sonde-continuite.sh (F4-S02, CHG-3402, RB-340)
# Démarre, suit ou arrête la charge de la sonde de continuité (TestRun « sonde-continuite » de k6).
#
#   outils/sonde-continuite.sh demarrer CHG-3404 [DUREE=3h]   # testid = sonde-continuite-CHG-3404
#   outils/sonde-continuite.sh etat
#   outils/sonde-continuite.sh arreter
#
# Depuis adm01, clone ~/src/resilience, avec un kubeconfig qui peut créer des TestRun et la ConfigMap
# dans l'espace k6 (identité OIDC de la plateforme, ou contexte de l'agent GitLab en CI).
set -euo pipefail

NS=k6
NOM=sonde-continuite
racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() { echo "Usage : $0 demarrer CHG-34XX [DUREE] | etat | arreter" >&2; exit 2; }
[[ $# -ge 1 ]] || usage

case "$1" in
  demarrer)
    [[ $# -ge 2 && "$2" =~ ^CHG-34[0-9]{2}$ ]] || usage
    duree="${3:-3h}"
    [[ "$duree" =~ ^[0-9]+[smh]$ ]] || { echo "durée attendue : 90m, 3h…" >&2; exit 2; }
    if kubectl -n "$NS" get testrun "$NOM" >/dev/null 2>&1; then
      echo "une sonde tourne déjà ($(kubectl -n "$NS" get testrun "$NOM" -o jsonpath='{.spec.arguments}')) : arrête-la d'abord" >&2
      exit 1
    fi
    kubectl -n "$NS" create configmap "$NOM" --from-file=sonde-continuite.js="$racine/continuite/sonde-continuite.js" \
      --dry-run=client -o yaml | kubectl apply -f -
    sed -e "s/sonde-continuite-CHG34XX/sonde-continuite-$2/" -e "s/DUREE_SONDE/$duree/" "$racine/continuite/testrun.yaml" | kubectl apply -f -
    echo "sonde lancée : testid=sonde-continuite-$2, durée $duree ; début à noter dans la fiche : $(date -Iseconds)"
    ;;
  etat)
    kubectl -n "$NS" get testrun "$NOM" -o custom-columns='NOM:.metadata.name,ETAPE:.status.stage,ARGUMENTS:.spec.arguments' 2>/dev/null ||
      echo "aucune sonde en cours"
    kubectl -n "$NS" get pods -l "k6_cr=$NOM" 2>/dev/null || true
    ;;
  arreter)
    # Supprimer le TestRun arrête les exécuteurs (l'opérateur supprime ses Jobs) ; la ConfigMap reste.
    kubectl -n "$NS" delete testrun "$NOM" --ignore-not-found
    echo "sonde arrêtée à $(date -Iseconds)"
    ;;
  *) usage ;;
esac
