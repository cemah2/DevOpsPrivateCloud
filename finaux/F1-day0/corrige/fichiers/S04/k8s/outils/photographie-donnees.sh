#!/usr/bin/env bash
# photographie-donnees.sh — photographie de l'état des données de k8s-par1, avant ou après une
# opération (F1-S04, CHG-3104 ; rejouée en F1-S11 pour comparer). plateforme/k8s, outils/.
#
#   outils/photographie-donnees.sh > ~/medisphere/docs/day0/reference-avant.md
#
# LECTURE SEULE. Aucune donnée de patient : des COMPTES et des NOMS d'objets. Identité : ton
# kubeconfig d'administration (comptes en base par « kubectl exec » sur l'instance primaire de CNPG,
# files par « rabbitmqctl list_queues » dans un pod de la grappe). Les Secrets ne sont jamais lus.
# Sortie : Markdown sur la sortie standard. Code 1 si une mesure est impossible (elle est notée
# « ÉCHEC » dans le tableau, la photographie reste utilisable).
set -euo pipefail

KUBECTL=(kubectl --request-timeout=20s)
echec=0

ligne() { printf '| %s | %s |\n' "$1" "$2"; }

# compte_rdv ESPACE — nombre de rendez-vous dans la base mediagenda de mediagenda-db.
# shellcheck disable=SC2329  # appelée par « mesure »
compte_rdv() {
  local pod
  pod="$("${KUBECTL[@]}" -n "$1" get pods -l cnpg.io/cluster=mediagenda-db,cnpg.io/instanceRole=primary \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)" || return 1
  [[ -n "$pod" ]] || return 1
  "${KUBECTL[@]}" -n "$1" exec "$pod" -c postgres -- psql -d mediagenda -tAc 'SELECT count(*) FROM rendez_vous'
}

mesure() {
  local nom="$1" v
  shift
  if v="$("$@" 2>/dev/null)" && [[ -n "$v" ]]; then
    ligne "$nom" "$v"
  else
    ligne "$nom" "ÉCHEC"
    echec=1
  fi
}

printf '# Référence des données — %s\n\n' "$(date -Iseconds)"
# shellcheck disable=SC2016  # accents graves Markdown, pas une substitution
printf '> Produit par `plateforme/k8s/outils/photographie-donnees.sh` (lecture seule). Comptes et noms seulement.\n\n'
printf '| Mesure | Valeur |\n|---|---|\n'

mesure "Rendez-vous en production (mediagenda-prod)" compte_rdv mediagenda-prod
mesure "Rendez-vous en recette (mediagenda-recette)" compte_rdv mediagenda-recette
mesure "Dernière archive WAL de mediagenda-db (prod)" \
  "${KUBECTL[@]}" -n mediagenda-prod get clusters.postgresql.cnpg.io mediagenda-db \
  -o jsonpath='{.status.lastArchivedWAL} à {.status.lastArchivedWALTime}'
mesure "Messages en file, vhost medinotif-prod" \
  bash -c "${KUBECTL[*]} -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmqctl list_queues -q -p medinotif-prod name messages | sort | paste -sd ';'"
mesure "Messages en file, vhost medinotif-recette" \
  bash -c "${KUBECTL[*]} -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmqctl list_queues -q -p medinotif-recette name messages | sort | paste -sd ';'"
mesure "ExternalSecret (total / Ready)" \
  bash -c "${KUBECTL[*]} get externalsecrets.external-secrets.io -A -o json | jq -r '\"\(.items | length) / \([.items[] | select(any(.status.conditions[]?; .type == \"Ready\" and .status == \"True\"))] | length)\"'"
mesure "Certificats cert-manager (total / Ready)" \
  bash -c "${KUBECTL[*]} get certificates.cert-manager.io -A -o json | jq -r '\"\(.items | length) / \([.items[] | select(any(.status.conditions[]?; .type == \"Ready\" and .status == \"True\"))] | length)\"'"
mesure "Certificat expirant le plus tôt" \
  bash -c "${KUBECTL[*]} get certificates.cert-manager.io -A -o json | jq -r '[.items[] | {n: \"\(.metadata.namespace)/\(.metadata.name)\", t: (.status.notAfter // \"?\")}] | sort_by(.t) | .[0] | \"\(.n) (\(.t))\"'"
mesure "Applications Argo CD (total / Synced+Healthy)" \
  bash -c "${KUBECTL[*]} -n argocd get applications.argoproj.io -o json | jq -r '\"\(.items | length) / \([.items[] | select(.status.sync.status == \"Synced\" and .status.health.status == \"Healthy\")] | length)\"'"
mesure "PVC (nombre, capacité totale en Gi)" \
  bash -c "${KUBECTL[*]} get pvc -A -o json | jq -r '\"\(.items | length), \([.items[].status.capacity.storage // \"0Gi\" | sub(\"Gi\$\"; \"\") | tonumber? // 0] | add) Gi\"'"
mesure "Versions des nœuds (kubelet)" \
  bash -c "${KUBECTL[*]} get nodes -o jsonpath='{range .items[*]}{.metadata.name}={.status.nodeInfo.kubeletVersion} {end}'"
mesure "Releases Helm de la couche de base" \
  bash -c "helm list -A -o json | jq -r '[.[] | \"\(.name)=\(.chart)\"] | sort | join(\" \")'"

printf '\n'
exit "$echec"
