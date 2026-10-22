# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E42.sh — M20-E42 « Panne : le cluster de l'agence est Unknown » : cluster lyo1 joignable par
# Argo CD (API d'Argo CD), Application de l'agence Synced et Healthy, aucun filtrage local de 6443
# sur lyo-k3s01, compte argocd-gestion toujours limité (pas cluster-admin), RB-200, journal, panne
# close. Sans objet après la destruction de lyo-k3s01 (mini-projet). Lecture seule.

# shellcheck source=_m20-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-expert.sh"

title "M20-E42 — Le cluster de l'agence est de nouveau géré"
require_cmd jq kubectl curl ssh

if _m20x_vm_absente 2201; then
  skip "cluster lyo-k3s01" "VM 2201 détruite (mini-projet M20-E46) : exercice sans objet"
elif ! _m20x_argo_lisible; then
  skip "Applications d'Argo CD" "le compte des checks ne lit pas les Applications (wb-checks-livraison, M20-E03)"
else
  _m20_e42_motif="${_m20x_lyo//./\\.}|lyo"
  _m20_e42_json="$(kube -n "$_m20x_ns" get applications.argoproj.io -o json 2>/dev/null)"
  _m20_e42_apps="$(jq -r --arg r "$_m20_e42_motif" '.items[] | select(((.spec.destination.server // "") | test($r)) or ((.spec.destination.name // "") | test("lyo"))) | .metadata.name' <<<"$_m20_e42_json")"
  _m20_e42_ns_dest="$(jq -r --arg r "$_m20_e42_motif" '[.items[] | select(((.spec.destination.server // "") | test($r)) or ((.spec.destination.name // "") | test("lyo"))) | .spec.destination.namespace // empty][0] // "default"' <<<"$_m20_e42_json")"
  if [[ -z "$_m20_e42_apps" ]]; then
    check_cmd "au moins une Application déploie sur le cluster de l'agence (M20-E26)" false
  else
    for _m20_e42_a in $_m20_e42_apps; do
      check_cmd "$_m20_e42_a : Synced, Healthy" _m20x_app_saine "$_m20_e42_a"
    done
  fi
  _m20_e42_connecte() {
    _m20x_argocd_api clusters | jq -e --arg r "$_m20_e42_motif" '[.items[]? | select((.server | test($r)) or ((.name // "") | test("lyo")))
      | select(((.info.connectionState.status // .connectionState.status) // "") == "Successful")] | length == 1' >/dev/null 2>&1
  }
  if _m20x_argocd_api clusters >/dev/null 2>&1; then
    check_cmd "API d'Argo CD : cluster de l'agence (lyo-k3s01) en état de connexion « Successful »" _m20_e42_connecte
  else
    skip "état de connexion du cluster" "API d'Argo CD illisible avec ~/.config/workbook/argocd-checks.token (M20-E03)"
  fi
  check_cmd "lyo-k3s01 : aucune règle nftables qui refuse l'API (6443)" \
    _m20x_noeud_lyo '! nft list ruleset 2>/dev/null | grep -E "dport (6443|\{[^}]*6443)" | grep -qE "drop|reject"'
  _m20_e42_sa="$(_m20x_noeud_lyo_sortie 'k3s kubectl get sa -A --no-headers 2>/dev/null' | awk '$2 == "argocd-gestion" {print $1; exit}')"
  if [[ -z "$_m20_e42_sa" ]]; then
    check_cmd "lyo-k3s01 : compte de service argocd-gestion présent" false
  else
    check_cmd "lyo-k3s01 : argocd-gestion n'est pas administrateur du cluster" \
      _m20x_noeud_lyo "[ \"\$(k3s kubectl auth can-i '*' '*' --all-namespaces --as=system:serviceaccount:$_m20_e42_sa:argocd-gestion 2>/dev/null)\" = no ]"
    check_cmd "lyo-k3s01 : argocd-gestion gère encore l'espace $_m20_e42_ns_dest (droits rétablis)" \
      _m20x_noeud_lyo "[ \"\$(k3s kubectl auth can-i patch deployments.apps -n $_m20_e42_ns_dest --as=system:serviceaccount:$_m20_e42_sa:argocd-gestion 2>/dev/null)\" = yes ]"
  fi
fi
check_cmd "RB-200 : section sur le cluster distant injoignable" _m20x_doc_contient "$_m20x_rb200" '^#+ .*(cluster|Unknown)'
check_cmd "journal de diagnostic de INC-4742 commité (docs/kubernetes/journal/)" _m20x_journal 'INC-4742'
check_cmd "panne M20-E42 close (lab/bin/break 20 42 --annuler après réparation)" _m20x_aucune_panne_active E42
