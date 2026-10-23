#!/usr/bin/env bash
# plateforme/k8s — outils/approuver-csr-kubelet.sh (F1-S08, PLAT-3108)
# Approbation MANUELLE et vérifiée des certificats de service des kubelets (serverTLSBootstrap, M26-E25)
# tant que kubelet-csr-approver (Application d'Argo CD) n'est pas revenu. Mêmes contrôles que lui :
#   - signataire kubernetes.io/kubelet-serving, demande en attente ;
#   - demandeur system:node:<nœud>, nœud connu du cluster ET de la liste des six nœuds ;
#   - noms et adresses demandés ⊂ { nom court, FQDN en par1.medisphere.internal, adresses du nœud
#     publiées dans son statut } ; rien d'autre (pas de joker, pas d'adresse d'un autre nœud).
# Toute demande refusée par ces contrôles est laissée en attente et affichée : on enquête.
#   outils/approuver-csr-kubelet.sh            # simulation : affiche ce qui serait approuvé
#   outils/approuver-csr-kubelet.sh --approuver
# Chaque approbation est un GESTE MANUEL de la fenêtre (chronologie, F1-S08).

set -euo pipefail

CTX="${KUBECTL_CONTEXTE:-k8s-par1}"
NOEUDS=" k8s-cp01 k8s-cp02 k8s-cp03 k8s-w01 k8s-w02 k8s-w03 "
DOMAINE=par1.medisphere.internal
APPROUVER=0
[[ "${1:-}" == --approuver ]] && APPROUVER=1

k() { kubectl --context "$CTX" "$@"; }

k get csr -o json | jq -r '.items[]
  | select(.spec.signerName == "kubernetes.io/kubelet-serving")
  | select((.status.conditions // []) | length == 0)
  | "\(.metadata.name) \(.spec.username) \(.spec.request)"' |
while read -r csr demandeur requete; do
  noeud="${demandeur#system:node:}"
  if [[ "$demandeur" != system:node:* || "$NOEUDS" != *" $noeud "* ]]; then
    echo "LAISSÉE  $csr : demandeur inattendu ($demandeur)"
    continue
  fi
  permis="$(k get node "$noeud" -o json 2>/dev/null | jq -r --arg d "$DOMAINE" \
    '.metadata.name as $n | ([$n, "\($n).\($d)"] + [.status.addresses[].address]) | unique | .[]')" || permis=""
  if [[ -z "$permis" ]]; then
    echo "LAISSÉE  $csr : nœud $noeud inconnu du cluster"
    continue
  fi
  demandes="$(base64 -d <<<"$requete" | openssl req -noout -text 2>/dev/null |
    sed -n '/Subject Alternative Name/{n;p}' | tr ',' '\n' | sed -E 's/^[[:space:]]*(DNS|IP Address)://' | sort -u)"
  hors="$(comm -23 <(printf '%s\n' "$demandes" | sort -u) <(printf '%s\n' "$permis" | sort -u))"
  if [[ -z "$demandes" || -n "$hors" ]]; then
    echo "LAISSÉE  $csr ($noeud) : noms ou adresses hors du nœud : ${hors:-aucun nom demandé}"
    continue
  fi
  if ((APPROUVER)); then
    k certificate approve "$csr" >/dev/null
    echo "APPROUVÉE $csr ($noeud) : $(paste -sd' ' <<<"$demandes")"
  else
    echo "À APPROUVER $csr ($noeud) : $(paste -sd' ' <<<"$demandes")  [simulation : --approuver]"
  fi
done
