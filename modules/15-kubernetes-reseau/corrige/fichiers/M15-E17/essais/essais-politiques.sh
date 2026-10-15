#!/usr/bin/env bash
# ~/m15/e17/essais-politiques.sh — preuves de M15-E17 (depuis adm01, identité d'administration).
# Positifs et négatifs ; les sorties de Hubble vont dans ~/m15/e17/.
set -uo pipefail
U=https://mediagenda-recette.apps.par1.medisphere.internal
D="$HOME/m15/e17"; mkdir -p "$D"
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

echo "== Positifs (attendu 200 / 201)"
echo "sante   $(code "$U/sante")"
echo "pret    $(code "$U/pret")"
echo "liste   $(code "$U/api/v1/rendez-vous?limite=5")"
echo "creneaux $(code "$U/api/v1/creneaux?date=$(date +%F)")"
echo "== Négatifs (attendu 403 du proxy L7)"
echo "metrics $(code "$U/metrics")"
echo "PUT     $(code -X PUT "$U/api/v1/rendez-vous/1")"
echo "docs    $(code "$U/docs")"
echo "== Latéral : un pod de wb-essais vers PostgreSQL de la recette (attendu : échec)"
kubectl -n wb-essais run essai-lateral --rm -i --restart=Never --quiet \
  --image=registry.par1.medisphere.internal/k8s/e2e-test-images/agnhost:2.61 \
  -- connect --timeout=3s postgresql.mediagenda-recette.svc.cluster.local:5432 \
  && echo "ÉCHEC : connexion établie" || echo "OK : connexion refusée ou expirée"
echo "== Hubble : chutes dans la recette pendant les essais"
hubble observe -n mediagenda-recette --verdict DROPPED --since 5m -o compact | tee "$D/hubble-drops.txt"
hubble observe -n mediagenda-recette --since 5m --protocol http -o compact | tee "$D/hubble-http.txt"
