#!/usr/bin/env bash
# ~/m14/e11/matrice-droits.sh — matrice des droits attendus, par usurpation d'identité (--as).
# À lancer depuis adm01 avec TON kubeconfig (groupe medisphere:plateforme-admins, qui a « impersonate »).
# Sortie : une ligne par cas, OK si la réponse de l'API est celle attendue. Code 1 si un écart.
# Usage : matrice-droits.sh            (lecture seule : « auth can-i » ne crée rien)
set -euo pipefail

ecarts=0
# cas UTILISATEUR GROUPE ESPACE VERBE RESSOURCE ATTENDU(yes|no)
cas() {
  local u="$1" g="$2" ns="$3" verbe="$4" res="$5" attendu="$6" obtenu
  local -a espace=()
  [[ "$ns" == "-" ]] || espace=(-n "$ns")
  obtenu="$(kubectl auth can-i "$verbe" "$res" "${espace[@]}" --as="$u" --as-group="$g" 2>/dev/null || true)"
  if [[ "$obtenu" == "$attendu" ]]; then
    printf 'OK     %-14s %-28s %-20s %-8s %-22s %s\n' "$u" "$g" "$ns" "$verbe" "$res" "$obtenu"
  else
    printf 'ÉCART  %-14s %-28s %-20s %-8s %-22s attendu %s, obtenu %s\n' "$u" "$g" "$ns" "$verbe" "$res" "$attendu" "${obtenu:-?}"
    ecarts=$((ecarts + 1))
  fi
}

D="medisphere:mediagenda-devs"; L="medisphere:lecture"
# Équipe MédiAgenda en dev : écrit ses charges, gère ses Secrets, entre dans ses pods.
cas julien.petit "$D" mediagenda-dev     create deployments.apps     yes
cas julien.petit "$D" mediagenda-dev     patch  deployments/scale    yes
cas julien.petit "$D" mediagenda-dev     create pods/exec            yes
cas julien.petit "$D" mediagenda-dev     create secrets              yes
cas julien.petit "$D" mediagenda-dev     get    secrets              yes
# … mais ne touche ni aux quotas, ni au RBAC, ni à l'espace lui-même.
cas julien.petit "$D" mediagenda-dev     update resourcequotas       no
cas julien.petit "$D" mediagenda-dev     create rolebindings.rbac.authorization.k8s.io no
cas julien.petit "$D" -                  delete namespaces           no
# En recette : lecture seule, et pas de Secrets.
cas julien.petit "$D" mediagenda-recette get    pods/log             yes
cas julien.petit "$D" mediagenda-recette create deployments.apps     no
cas julien.petit "$D" mediagenda-recette create pods/exec            no
cas julien.petit "$D" mediagenda-recette get    secrets              no
# Ailleurs : rien.
cas julien.petit "$D" kube-system        list   pods                 no
cas julien.petit "$D" -                  list   nodes                no
# Groupe lecture : tout voir, sauf les Secrets ; rien écrire.
cas nadia.roussel "$L" kube-system       list   pods                 yes
cas nadia.roussel "$L" -                 list   nodes                yes
cas nadia.roussel "$L" mediagenda-dev    get    secrets              no
cas nadia.roussel "$L" mediagenda-dev    delete pods                 no
# Un authentifié quelconque : rien au-delà de la découverte.
cas inconnu "system:authenticated" mediagenda-dev list pods          no

echo
if ((ecarts)); then echo "$ecarts écart(s)."; exit 1; fi
echo "Matrice conforme."
