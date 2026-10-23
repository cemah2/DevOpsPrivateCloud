#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# plateforme/k8s — outils/day0/50-argocd.sh (F1-S10, PLAT-3110)
# Un seul objet créé à la main : l'application racine de plateforme/gitops (M20-E06). Ensuite on
# OBSERVE la convergence ; chaque blocage se corrige par une MR (jamais par kubectl), noté au journal.
# Fin : toutes les Applications Synced/Healthy sauf celles qui attendent leurs données (F1-S11).

# shellcheck source=../../../../S07/k8s/outils/day0/commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/commun.sh"

PHASE=argocd
GITOPS="$DAY0_SRC/gitops"
export ATTENTE="${ATTENTE:-mediagenda-recette mediagenda-prod portail}"

outils_requis kubectl jq column

creer_racine() {
  k apply --server-side -f "$GITOPS/racine/racine.yaml"
}

# convergee — plus aucune Application non saine hors de la liste d'attente.
convergee() {
  local reste
  reste="$(k -n argocd get applications.argoproj.io -o json | jq -r --arg a " $ATTENTE " '
    [.items[] | select(($a | contains(" " + .metadata.name + " ")) | not)
              | select(.status.sync.status != "Synced" or .status.health.status != "Healthy")] | length')"
  [[ "$reste" == 0 ]]
}

suivre() {
  local debut=$SECONDS
  until convergee; do
    clear 2>/dev/null || true
    printf 'Convergence depuis %s min — Applications non saines :\n\n' "$(((SECONDS - debut) / 60))"
    "$GITOPS/outils/etat-applications.sh" || true
    printf '\nUn blocage qui ne se résout pas seul en deux tours : MR, puis note dans la chronologie.\n'
    sleep 60
    if ((SECONDS - debut > 3 * 3600)); then echo "3 h sans convergence : arrêt du suivi." >&2; return 1; fi
  done
}

csr_en_attente() {
  [[ "$(k get csr -o json | jq '[.items[] | select(.spec.signerName == "kubernetes.io/kubelet-serving" and ((.status.conditions // []) | length == 0))] | length')" == 0 ]]
}

etape "$PHASE" "application racine (seul objet créé à la main)" creer_racine
etape "$PHASE" "convergence de la plateforme" suivre
etape "$PHASE" "approbateur des certificats de kubelets revenu, aucune demande en attente" attendre 900 "CSR traitées" csr_en_attente
jalon "$PHASE" "plateforme reconstruite" "attendues pour S11 : $ATTENTE ; lab/bin/check F1 10"
