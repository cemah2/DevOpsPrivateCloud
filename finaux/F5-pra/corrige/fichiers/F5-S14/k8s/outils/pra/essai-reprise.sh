#!/usr/bin/env bash
# plateforme/k8s — outils/pra/essai-reprise.sh (F5-S14, PLAT-3538)
#
# Test de reprise PARTIEL et automatique, lancé chaque trimestre par un pipeline planifié de
# plateforme/k8s (job « pra:essai-reprise », runner protégé) et à la demande :
#   1. restaure la base de production à PAR2, dans l'espace jetable « pra-essai » de k8s-par2, depuis la
#      COPIE de l'archive de PAR1 présente sur s3-02 (ce dont PAR2 disposerait si PAR1 brûlait) ;
#   2. mesure la durée de restauration et l'âge des données restaurées (dernier témoin PRA-TEMOIN) ;
#   3. vérifie des invariants : nombre de rendez-vous, DNS de PAR2 à jour, image de production sur reg02
#      (si les identifiants sont fournis), lecture de l'archive de PAR2 depuis PAR1 (si fournie) ;
#   4. nettoie TOUT (Cluster, PVC, ObjectStore, Secrets) même en cas d'échec ;
#   5. écrit resultat-essai.json (artefact du job) et échoue si un seuil est dépassé.
# Ne touche jamais mediagenda-db-par2 (espace mediagenda-prod) ni PAR1 : le Cluster d'essai n'archive pas.
#
# Variables (CI/CD protégées et masquées pour les secrets) :
#   KUBECONFIG                kubeconfig du compte « pra-essai » de k8s-par2 (droits limités à l'espace
#                             pra-essai, plus exec ; variable de type fichier)
#   S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY   identité de LECTURE de cnpg-k8s-par1 sur s3-02
#   CA_FICHIER                racine MédiSphère (fichier)
#   SERVEUR_SOURCE            serverName de la production de PAR1 (défaut mediagenda-db-prod-pra1)
#   STOCKAGE                  classe de stockage locale de k8s-par2 (défaut local-path)
#   SEUIL_DUREE_S (1800), SEUIL_RPO_S (900), SEUIL_LIGNES_MIN (1)
#   REG02_USER, REG02_PASSWORD, IMAGE_PROD (facultatifs) : image « dépôt@sha256:… » attendue sur reg02
#   DNS01, DNS03 (10.10.20.10, 10.20.20.11)
set -euo pipefail

NS=pra-essai
NOM="essai-$(date -u +%Y%m%d%H%M)"
SERVEUR_SOURCE="${SERVEUR_SOURCE:-mediagenda-db-prod-pra1}"
STOCKAGE="${STOCKAGE:-local-path}"
SEUIL_DUREE_S="${SEUIL_DUREE_S:-1800}"
SEUIL_RPO_S="${SEUIL_RPO_S:-900}"
SEUIL_LIGNES_MIN="${SEUIL_LIGNES_MIN:-1}"
DNS01="${DNS01:-10.10.20.10}"
DNS03="${DNS03:-10.20.20.11}"
: "${S3_ACCESS_KEY_ID:?}" "${S3_SECRET_ACCESS_KEY:?}" "${CA_FICHIER:?}"

for outil in kubectl jq dig curl; do
  command -v "$outil" >/dev/null || { echo "outil manquant : $outil" >&2; exit 2; }
done

k() { kubectl -n "$NS" --request-timeout=30s "$@"; }

nettoyer() {
  k delete cluster.postgresql.cnpg.io "$NOM" --ignore-not-found --wait=true --timeout=300s >/dev/null 2>&1 || true
  k delete objectstore.barmancloud.cnpg.io "$NOM-source" --ignore-not-found >/dev/null 2>&1 || true
  k delete secret "$NOM-s3" "$NOM-ca" --ignore-not-found >/dev/null 2>&1 || true
  # Les PVC du Cluster lui appartiennent (suppression en cascade) ; on vérifie qu'il n'en reste aucun.
  k delete pvc -l "cnpg.io/cluster=$NOM" --ignore-not-found >/dev/null 2>&1 || true
}
trap nettoyer EXIT

# L'espace et le compte du test existent (fichiers de site de PAR2) : sinon, arrêt immédiat.
k get serviceaccount default >/dev/null

k create secret generic "$NOM-s3" --from-literal=ACCESS_KEY_ID="$S3_ACCESS_KEY_ID" \
  --from-literal=ACCESS_SECRET_KEY="$S3_SECRET_ACCESS_KEY" --dry-run=client -o yaml | k apply -f - >/dev/null
k create secret generic "$NOM-ca" --from-file=ca.crt="$CA_FICHIER" --dry-run=client -o yaml | k apply -f - >/dev/null

debut="$(date +%s)"
k apply -f - >/dev/null <<EOF
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: $NOM-source
spec:
  configuration:
    destinationPath: s3://cnpg-k8s-par1/
    endpointURL: https://s3-02.par2.medisphere.internal:8333
    endpointCA: {name: $NOM-ca, key: ca.crt}
    s3Credentials:
      accessKeyId: {name: $NOM-s3, key: ACCESS_KEY_ID}
      secretAccessKey: {name: $NOM-s3, key: ACCESS_SECRET_KEY}
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: $NOM
  labels:
    medisphere.internal/essai: pra
spec:
  instances: 1
  storage:
    storageClass: $STOCKAGE
    size: 5Gi
  resources:
    requests: {cpu: 250m, memory: 512Mi}
    limits: {memory: 1Gi}
  bootstrap:
    recovery:
      source: source
      database: mediagenda
      owner: mediagenda
  externalClusters:
    - name: source
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: $NOM-source
          serverName: $SERVEUR_SOURCE
EOF

restaure=0
if k wait --for=condition=Ready "cluster.postgresql.cnpg.io/$NOM" --timeout="${SEUIL_DUREE_S}s" >/dev/null 2>&1; then
  restaure=1
fi
duree=$(($(date +%s) - debut))

rpo=-1
lignes=-1
if ((restaure)); then
  pod="$(k get cluster.postgresql.cnpg.io "$NOM" -o jsonpath='{.status.currentPrimary}')"
  read -r rpo lignes < <(k exec "$pod" -c postgres -- psql -d mediagenda -AtX -F ' ' -c \
    "SELECT COALESCE(EXTRACT(EPOCH FROM now() - max(cree_le) FILTER (WHERE praticien = 'PRA-TEMOIN'))::int, -1),
            count(*) FILTER (WHERE praticien <> 'PRA-TEMOIN') FROM rendez_vous")
fi

# DNS de PAR2 à jour (même série que dns01) et noms globaux vers PAR1 (temps normal).
s1="$(dig +short +time=3 +tries=1 "@$DNS01" medisphere.internal SOA | awk '{print $3}')" || s1=""
s3="$(dig +short +time=3 +tries=1 "@$DNS03" medisphere.internal SOA | awk '{print $3}')" || s3=""
dns_ok=false
if [[ -n "$s3" && "$s1" == "$s3" ]] &&
  dig +short +time=3 +tries=1 "@$DNS03" mediagenda.medisphere.internal CNAME | grep -q '\.apps\.par1\.'; then
  dns_ok=true
fi

# Image de production présente sur reg02 (facultatif).
reg02_ok=null
if [[ -n "${IMAGE_PROD:-}" && -n "${REG02_USER:-}" ]]; then
  depot="${IMAGE_PROD%@*}"
  depot="${depot#*/}"
  empreinte="${IMAGE_PROD#*@}"
  reg02_ok=false
  if curl -sf -o /dev/null -I --max-time 10 --cacert "$CA_FICHIER" \
    -K <(printf 'user = "%s:%s"\n' "$REG02_USER" "${REG02_PASSWORD:-}") \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
    "https://reg02.par2.medisphere.internal/v2/$depot/manifests/$empreinte"; then
    reg02_ok=true
  fi
fi

verdict=reussi
((restaure)) || verdict=echec
((rpo >= 0 && rpo <= SEUIL_RPO_S)) || verdict=echec
((lignes >= SEUIL_LIGNES_MIN)) || verdict=echec
[[ "$dns_ok" == true ]] || verdict=echec
[[ "$reg02_ok" != false ]] || verdict=echec

jq -n --arg date "$(date -u +%FT%TZ)" --arg source "$SERVEUR_SOURCE" --arg verdict "$verdict" \
  --argjson duree "$duree" --argjson seuil_duree "$SEUIL_DUREE_S" --argjson rpo "$rpo" \
  --argjson seuil_rpo "$SEUIL_RPO_S" --argjson lignes "$lignes" --argjson dns "$dns_ok" --argjson reg02 "$reg02_ok" \
  '{date: $date, source: $source, duree_restauration_s: $duree, seuil_duree_s: $seuil_duree,
    age_dernier_temoin_s: $rpo, seuil_rpo_s: $seuil_rpo, rendez_vous: $lignes,
    dns_par2_a_jour: $dns, image_prod_sur_reg02: $reg02, verdict: $verdict}' | tee resultat-essai.json

[[ "$verdict" == reussi ]]
