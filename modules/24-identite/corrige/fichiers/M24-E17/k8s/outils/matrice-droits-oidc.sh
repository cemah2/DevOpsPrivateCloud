#!/usr/bin/env bash
# outils/matrice-droits-oidc.sh — matrice des droits des GROUPES DE L'ANNUAIRE sur k8s-par1 (M24-E17).
#
# Pour chaque cas : « kubectl auth can-i » en usurpant une identité OIDC (--as=oidc:<personne>
# --as-group=oidc:<groupe>), réponse comparée à l'attendu du modèle d'autorisation
# (docs/securite/identite/modele-autorisation.md, M24-E10). Lecture seule : can-i ne crée rien.
# Usurper une identité exige le verbe « impersonate » : lance-le avec une identité plateforme-admins.
#
# Usage : outils/matrice-droits-oidc.sh [CONTEXTE]     (défaut : k8s-par1-oidc)
# Sortie : une ligne OK/ÉCART par cas ; code 0 si la matrice est conforme, 1 au moindre écart,
# 2 si l'API ne répond pas.
set -euo pipefail

contexte="${1:-k8s-par1-oidc}"
ecarts=0

kubectl --context "$contexte" version >/dev/null 2>&1 || {
  echo "API injoignable avec le contexte $contexte (jeton expiré ? relance une commande kubectl pour te reconnecter)" >&2
  exit 2
}

# cas PERSONNE GROUPE ESPACE(- = cluster) VERBE RESSOURCE ATTENDU(yes|no)
cas() {
  local personne="$1" groupe="$2" ns="$3" verbe="$4" res="$5" attendu="$6" obtenu
  local -a espace=()
  [[ "$ns" == "-" ]] || espace=(-n "$ns")
  obtenu="$(kubectl --context "$contexte" auth can-i "$verbe" "$res" "${espace[@]}" \
    --as="oidc:$personne" --as-group="oidc:$groupe" 2>/dev/null || true)"
  if [[ "$obtenu" == "$attendu" ]]; then
    printf 'OK     %-15s %-18s %-19s %-7s %-34s %s\n' "$personne" "$groupe" "$ns" "$verbe" "$res" "$obtenu"
  else
    printf 'ÉCART  %-15s %-18s %-19s %-7s %-34s attendu %s, obtenu %s\n' \
      "$personne" "$groupe" "$ns" "$verbe" "$res" "$attendu" "${obtenu:-?}"
    ecarts=$((ecarts + 1))
  fi
}

# plateforme-admins : tout.
cas karim.benali plateforme-admins kube-system  delete pods                      yes
cas karim.benali plateforme-admins -            create clusterrolebindings.rbac.authorization.k8s.io yes

# plateforme : tout lire sauf les Secrets ; écrire dans wb-essais seulement.
cas lucas.martin plateforme        kube-system  list   pods                      yes
cas lucas.martin plateforme        -            list   nodes                     yes
cas lucas.martin plateforme        argocd       list   applications.argoproj.io  yes
cas lucas.martin plateforme        supervision  list   prometheusrules.monitoring.coreos.com yes
cas lucas.martin plateforme        kube-system  get    secrets                   no
cas lucas.martin plateforme        argocd       list   secrets                   no
cas lucas.martin plateforme        kube-system  delete pods                      no
cas lucas.martin plateforme        mediagenda-prod create pods/exec              no
cas lucas.martin plateforme        wb-essais    create deployments.apps          yes
cas lucas.martin plateforme        wb-essais    create secrets                   yes
cas lucas.martin plateforme        -            create namespaces                no

# mediagenda : « edit » en dev (Secrets de l'espace compris), « view » en recette et prod, rien ailleurs.
cas julien.petit mediagenda        mediagenda-dev     create pods/exec           yes
cas julien.petit mediagenda        mediagenda-dev     patch  deployments.apps    yes
cas julien.petit mediagenda        mediagenda-dev     get    secrets             yes
cas julien.petit mediagenda        mediagenda-dev     create rolebindings.rbac.authorization.k8s.io no
cas julien.petit mediagenda        mediagenda-recette get    pods/log            yes
cas julien.petit mediagenda        mediagenda-recette create pods/exec           no
cas julien.petit mediagenda        mediagenda-prod    list   pods                yes
cas julien.petit mediagenda        mediagenda-prod    create pods/exec           no
cas julien.petit mediagenda        mediagenda-prod    get    secrets             no
cas julien.petit mediagenda        medidoc-dev        list   pods                no
cas julien.petit mediagenda        -                  list   nodes               no

# medidoc : lecture de ses deux espaces seulement.
cas essai.medidoc medidoc          medidoc-recette    get    pods/log            yes
cas essai.medidoc medidoc          medidoc-dev        patch  deployments.apps    no
cas essai.medidoc medidoc          medidoc-dev        get    secrets             no

# support : tout lire sauf Secrets et composants, rien écrire.
cas nadia.roussel support          kube-system  list   pods                      yes
cas nadia.roussel support          -            list   nodes                     yes
cas nadia.roussel support          mediagenda-prod get secrets                   no
cas nadia.roussel support          mediagenda-prod delete pods                   no
cas nadia.roussel support          argocd       list   applications.argoproj.io  no

# securite : lire, et lire le RBAC ; jamais les Secrets ni l'écriture.
cas sophie.laurent securite        -            list   clusterrolebindings.rbac.authorization.k8s.io yes
cas sophie.laurent securite        kube-system  list   pods                      yes
cas sophie.laurent securite        mediagenda-prod list rolebindings.rbac.authorization.k8s.io yes
cas sophie.laurent securite        mediagenda-prod get secrets                   no
cas sophie.laurent securite        -            create clusterrolebindings.rbac.authorization.k8s.io no

# direction, ou un groupe inconnu : rien au-delà de la découverte.
cas claire.morel direction         mediagenda-prod list pods                     no
# Le préfixe protège les groupes du système : un groupe « system:masters » de l'annuaire deviendrait
# « oidc:system:masters », qui n'a aucun droit.
cas intrus       system:masters    kube-system  list   secrets                   no

echo
if ((ecarts)); then
  echo "$ecarts écart(s) : la matrice ne correspond pas au modèle d'autorisation."
  exit 1
fi
echo "Matrice conforme au modèle d'autorisation."
