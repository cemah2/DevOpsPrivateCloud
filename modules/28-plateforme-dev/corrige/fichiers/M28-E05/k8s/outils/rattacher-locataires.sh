#!/usr/bin/env bash
# plateforme/k8s — outils/rattacher-locataires.sh (M28-E05, PLAT-2905)
# Pose sur chaque espace d'équipe EXISTANT la référence de propriétaire vers son Tenant Capsule, comme
# le documente Capsule (« Adding Namespace to a Tenant »), après avoir vérifié que :
#   - le Tenant existe et est protégé (spec.preventDeletion: true ET annotation Argo CD Delete=false) ;
#   - l'espace porte déjà l'étiquette capsule.clastix.io/tenant de ce locataire et son étiquette
#     medisphere.internal/environnement (posées par « task espaces ») ;
#   - aucune AUTRE référence de propriétaire n'existe sur l'espace.
# Idempotent : un espace déjà rattaché à ce Tenant (même UID) est laissé tel quel.
# Usage : outils/rattacher-locataires.sh [--a-blanc]
#   --a-blanc : affiche ce qui serait fait (et fait passer chaque patch par --dry-run=server).
# Identité : la tienne (groupe oidc:plateforme-admins, administrateur Capsule) ; contexte k8s-par1.
# Retour arrière d'un espace (AVANT toute suppression de Tenant) :
#   kubectl patch namespace <espace> --type=merge -p '{"metadata":{"labels":{"capsule.clastix.io/tenant":null},"ownerReferences":[]}}'
set -euo pipefail

# espace:locataire
RATTACHEMENTS=(
  mediagenda-dev:mediagenda
  mediagenda-recette:mediagenda
  mediagenda-prod:mediagenda
  mediagenda-secours:mediagenda
  medidoc-dev:medidoc
  medidoc-recette:medidoc
  medinotif-recette:medinotif
  medinotif-prod:medinotif
)

a_blanc=()
if [[ "${1:-}" == "--a-blanc" ]]; then
  a_blanc=(--dry-run=server)
elif [[ $# -gt 0 ]]; then
  echo "usage : $0 [--a-blanc]" >&2
  exit 2
fi

command -v jq >/dev/null || { echo "jq est nécessaire" >&2; exit 2; }

erreur=0
for r in "${RATTACHEMENTS[@]}"; do
  ns="${r%%:*}"
  tenant="${r##*:}"

  t_json="$(kubectl get tenants.capsule.clastix.io "$tenant" -o json 2>/dev/null)" || {
    echo "KO  $ns : Tenant $tenant introuvable (Application « locataires » synchronisée ?)" >&2
    erreur=1; continue
  }
  if ! jq -e '.spec.preventDeletion == true and ((.metadata.annotations["argocd.argoproj.io/sync-options"] // "") | test("Delete=false"))' >/dev/null <<<"$t_json"; then
    echo "KO  $ns : Tenant $tenant NON protégé (preventDeletion et Delete=false exigés) — rien n'est fait" >&2
    erreur=1; continue
  fi
  uid="$(jq -r '.metadata.uid' <<<"$t_json")"

  ns_json="$(kubectl get namespace "$ns" -o json 2>/dev/null)" || {
    echo "--  $ns : espace absent, ignoré"
    continue
  }
  if ! jq -e --arg t "$tenant" '.metadata.labels["capsule.clastix.io/tenant"] == $t and (.metadata.labels["medisphere.internal/environnement"] // "") != ""' >/dev/null <<<"$ns_json"; then
    echo "KO  $ns : étiquettes capsule.clastix.io/tenant=$tenant et medisphere.internal/environnement attendues (task espaces)" >&2
    erreur=1; continue
  fi
  if jq -e --arg u "$uid" '[.metadata.ownerReferences[]? | select(.uid == $u)] | length == 1' >/dev/null <<<"$ns_json"; then
    echo "OK  $ns : déjà rattaché à $tenant"
    continue
  fi
  if jq -e '(.metadata.ownerReferences // []) | length > 0' >/dev/null <<<"$ns_json"; then
    echo "KO  $ns : porte déjà une autre référence de propriétaire — à examiner à la main" >&2
    erreur=1; continue
  fi

  patch="$(jq -cn --arg t "$tenant" --arg u "$uid" '{metadata: {ownerReferences: [{
    apiVersion: "capsule.clastix.io/v1beta2", kind: "Tenant", name: $t, uid: $u,
    controller: true, blockOwnerDeletion: true}]}}')"
  if kubectl patch namespace "$ns" --type=merge -p "$patch" "${a_blanc[@]}" >/dev/null; then
    echo "OK  $ns : rattaché à $tenant${a_blanc:+ (à blanc)}"
  else
    echo "KO  $ns : le patch a été refusé" >&2
    erreur=1
  fi
done

echo
kubectl get tenants.capsule.clastix.io -o custom-columns='LOCATAIRE:.metadata.name,ETAT:.status.state,ESPACES:.status.size' || true
exit "$erreur"
