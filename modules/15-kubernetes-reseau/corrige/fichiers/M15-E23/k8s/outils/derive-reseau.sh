#!/usr/bin/env bash
# outils/derive-reseau.sh — plateforme/k8s (M15-E23). Compare le réseau DÉCRIT dans le dépôt et le
# cluster, SANS RIEN MODIFIER : kubectl diff (dry-run côté serveur), valeurs et versions des releases
# Helm, version de Cilium, étiquettes des nœuds. Code 0 : aucune dérive ; 1 : dérive ; 2 : erreur.
# Prérequis : identité d'administration (kubectl diff demande les droits d'écriture en dry-run),
# helm 4, cilium, jq, yq 4. À lancer depuis la racine du dépôt (task reseau:derive).
set -uo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
source composants/versions.env

derive=0
note() { printf '  %-14s %s\n' "$1" "$2"; }

# 1) Manifestes : kubectl diff renvoie 0 (identique), 1 (différent), >1 (erreur).
for cible in composants/cilium/lb-ipam composants/cilium/bgp composants/passerelles \
             composants/cert-manager/clusterissuer-step-ca-acme.yaml composants/coredns \
             espaces/passerelles.yaml espaces/mediagenda-recette/httproute-mediagenda.yaml; do
  [[ -e "$cible" ]] || { note "absent" "$cible"; derive=1; continue; }
  kubectl diff --server-side -f "$cible" >/tmp/derive.$$ 2>&1
  rc=$?
  case $rc in
    0) note "ok" "$cible" ;;
    1) note "DÉRIVE" "$cible"; sed 's/^/      /' /tmp/derive.$$; derive=1 ;;
    *) note "ERREUR" "$cible"; sed 's/^/      /' /tmp/derive.$$; rm -f /tmp/derive.$$; exit 2 ;;
  esac
done
for e in mediagenda-dev mediagenda-recette; do
  kubectl diff --server-side -n "$e" -f espaces/politiques-mediagenda/ >/tmp/derive.$$ 2>&1
  case $? in
    0) note "ok" "politiques ($e)" ;;
    1) note "DÉRIVE" "politiques ($e)"; sed 's/^/      /' /tmp/derive.$$; derive=1 ;;
    *) note "ERREUR" "politiques ($e)"; rm -f /tmp/derive.$$; exit 2 ;;
  esac
done
rm -f /tmp/derive.$$

# 2) Releases Helm : version du chart et valeurs fournies (sous-ensemble : chaque feuille du
#    fichier doit avoir la même valeur dans la release ; les valeurs ajoutées par la CLI cilium
#    lors de l'installation ne comptent pas comme une dérive).
sous_ensemble() { # $1 = JSON attendu, $2 = JSON réel → liste des chemins différents
  jq -rn --argjson a "$1" --argjson b "$2" \
    '$a | paths(scalars) as $p | select(($b | getpath($p)) != ($a | getpath($p))) | $p | map(tostring) | join(".")'
}
releve() { # release espace fichier version_attendue
  local reel att ecarts version
  version="$(helm list -n "$2" -o json | jq -r --arg r "$1" '.[] | select(.name == $r) | .chart' 2>/dev/null)"
  [[ -n "$version" ]] || { note "DÉRIVE" "release $1 absente ($2)"; derive=1; return; }
  if [[ -n "$4" && "$version" != *"-${4#v}" && "$version" != *"-$4" ]]; then
    note "DÉRIVE" "release $1 : chart $version, attendu $4"; derive=1
  fi
  reel="$(helm get values "$1" -n "$2" -o json)"
  att="$(yq -o json '.' "$3")"
  ecarts="$(sous_ensemble "$att" "$reel")"
  if [[ -n "$ecarts" ]]; then note "DÉRIVE" "valeurs de $1 : $(tr '\n' ' ' <<<"$ecarts")"; derive=1
  else note "ok" "release $1 ($version)"; fi
}
releve cert-manager cert-manager composants/cert-manager/values.yaml "$CERT_MANAGER_VERSION"
releve external-dns external-dns composants/external-dns/values.yaml "$EXTERNAL_DNS_CHART_VERSION"
releve cilium kube-system composants/cilium/values.yaml "$CILIUM_VERSION"

# 3) Étiquettes des nœuds.
if outils/etiqueter-noeuds.sh --verifier; then note "ok" "étiquettes des nœuds"; else derive=1; fi

if (( derive )); then echo "Dérive détectée."; exit 1; fi
echo "Aucune dérive."
