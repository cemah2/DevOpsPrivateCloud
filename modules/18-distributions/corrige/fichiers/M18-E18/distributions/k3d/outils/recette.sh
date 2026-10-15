#!/usr/bin/env bash
# shellcheck disable=SC2029,SC2094  # noms expansés côté adm01 volontairement ; tee distant ≠ fichier local
# k3d/outils/recette.sh — cluster de recette éphémère « recette-mediagenda » (M18-E18). Lancé depuis adm01.
# Usage : k3d/outils/recette.sh creer|detruire
# creer :
#   1. copie la configuration, les miroirs et la CA sur m18-dev01, y lance « k3d cluster create » ;
#   2. range le kubeconfig dans ~/.config/workbook/m18/recette-mediagenda.kubeconfig (600) ;
#   3. installe l'opérateur CloudNativePG (même version de chart que le helmfile.yaml de plateforme/k8s) ;
#   4. crée l'espace mediagenda-recette (étiquettes propriétaire/expiration) et le Secret harbor-pull ;
#   5. vérifie la signature du chart (digest de chart.env de mediagenda/deploiement), puis l'installe ;
#   6. attend /sante sur http://m18-dev01.par1.medisphere.internal:8080.
# detruire : « k3d cluster delete », suppression du kubeconfig et des fichiers copiés.
set -euo pipefail

nom=recette-mediagenda
hote="${M18_HOTE_RECETTE:-m18-dev01}"
fqdn="$hote.par1.medisphere.internal"
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"          # dossier k3d/
src="${WB_SRC:-$HOME/src}"
kc="$HOME/.config/workbook/m18/$nom.kubeconfig"
ca=/usr/local/share/ca-certificates/medisphere-root-ca.crt
cosign_pub="${WB_DEPOT:-$HOME/medisphere}/docs/registre/cosign.pub"
# Version du chart cnpg du Helmfile (fichier gabarit .gotmpl : lu comme du texte, pas par yq).
cnpg_version="$(awk '/- name: cnpg$/ {t=1} t && /version:/ {print $2; exit}' "$src/k8s/releases/30-stockage.yaml.gotmpl")"

journal() { printf '%s %s\n' "$(date +%T)" "$*"; }

creer() {
  # Version du chart de la recette partagée : c'est le dépôt qui fait foi (k8s-par1 est éteint).
  # shellcheck source=/dev/null
  . <(grep -E '^CHART_(REF|VERSION|DIGEST)=' "$src/mediagenda-deploiement/chart.env")
  : "${CHART_REF:?} ${CHART_VERSION:?} ${CHART_DIGEST:?}"
  [[ -n "$cnpg_version" ]] || { echo "version du chart cnpg introuvable" >&2; exit 1; }

  journal "T0+ copie des fichiers sur $hote"
  ssh "$hote" "sudo -n install -d -m 755 /opt/$nom"
  for f in "$ici/registries.yaml" "$ca"; do
    ssh "$hote" "sudo -n tee /opt/$nom/$(basename "$f") >/dev/null" < "$f"
  done
  ssh "$hote" "sudo -n tee /opt/$nom/config.yaml >/dev/null" < "$ici/$nom.yaml"

  journal "création du cluster (k3d)"
  ssh "$hote" "k3d cluster create --config /opt/$nom/config.yaml"
  install -d -m 700 "$(dirname "$kc")"
  ( umask 077; ssh "$hote" "k3d kubeconfig get $nom" > "$kc" )
  chmod 600 "$kc"
  export KUBECONFIG="$kc"
  kubectl wait --for=condition=Ready nodes --all --timeout=180s
  journal "T1 nœuds prêts"

  helm repo add cnpg https://cloudnative-pg.github.io/charts --force-update >/dev/null
  helm upgrade --install cnpg cnpg/cloudnative-pg --version "$cnpg_version" \
    -n cnpg-system --create-namespace --wait --timeout 5m
  journal "T2 opérateur CloudNativePG $cnpg_version prêt"

  expiration="$(date -d tomorrow +%F)"
  kubectl create namespace mediagenda-recette --dry-run=client -o yaml \
    | kubectl label --local -f - -o yaml medisphere.fr/proprietaire=mediagenda "medisphere.fr/expiration=$expiration" \
    | kubectl apply -f -
  "$src/k8s/outils/secret-tirage.sh" mediagenda-recette     # Secret harbor-pull (M14-E19), depuis harbor-k8s-pull.env

  hote_reg="${CHART_REF#oci://}"
  cosign verify --key "$cosign_pub" --insecure-ignore-tlog=true "${hote_reg}@${CHART_DIGEST}" >/dev/null
  journal "signature du chart ${CHART_VERSION} vérifiée (${CHART_DIGEST})"
  helm upgrade --install mediagenda "$CHART_REF" --version "$CHART_VERSION" -n mediagenda-recette \
    -f "$ici/$nom-values.yaml" --wait --timeout 10m
  journal "T3 release installée"

  for _ in $(seq 1 60); do
    if curl -fsS --max-time 3 "http://$fqdn:8080/sante" | jq -e '.version == "v1.1.0" and .environnement == "recette"' >/dev/null 2>&1; then
      journal "T4 /sante vert sur http://$fqdn:8080"
      return 0
    fi
    sleep 5
  done
  echo "/sante ne répond pas comme attendu" >&2
  return 1
}

detruire() {
  ssh "$hote" "k3d cluster delete $nom" || true
  ssh "$hote" "sudo -n rm -rf /opt/$nom"
  rm -f "$kc"
  journal "T5 cluster $nom détruit, kubeconfig supprimé"
}

case "${1:-}" in
  creer) creer ;;
  detruire) detruire ;;
  *) echo "usage : $0 creer|detruire" >&2; exit 2 ;;
esac
