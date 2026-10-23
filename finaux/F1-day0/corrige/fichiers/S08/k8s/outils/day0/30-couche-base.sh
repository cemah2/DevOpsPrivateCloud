#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# plateforme/k8s — outils/day0/30-couche-base.sh (F1-S08, PLAT-3108)
# Couche de base de k8s-par1 sur un cluster neuf (nœuds NotReady, aucun CNI), dans l'ordre RÉEL de ses
# dépendances. À lancer dans ~/src/k8s, avec DAY0_KUBECONFIG = admin.conf du nouveau cluster (20-noeuds.sh).
# Ce script range dans outils/day0/ (avec commun.sh, 10-gel.sh, 20-noeuds.sh) ; il appelle les tâches
# et fichiers existants du dépôt, il ne les remplace pas.
#
#   1. espaces de noms SEULS (pas « task appliquer » : espaces/ contient aussi les bases CNPG, qui ne
#      doivent naître que par récupération en F1-S11) ;
#   2. CRD Gateway API (avant Cilium : son contrôleur Gateway ne démarre que si elles existent) ;
#   3. Cilium (Helmfile), attente des agents ; étiquettes et taints des nœuds ; LB IPAM, BGP, CoreDNS ;
#   4. amorçage des Secrets (outils/amorcer-secrets.sh, session OIDC d'OpenBao) ;
#   5. cert-manager, émetteurs, ExternalDNS ; gw-par1 et apps-joker ;
#   6. carte VLAN 30 des travailleurs (k8s-reseau-stockage.yml : il attend des nœuds Ready) ;
#   7. contrôleur de snapshots, ceph-csi, CNPG + plugin Barman Cloud, Velero ;
#   8. certificats de service des kubelets (approbation vérifiée), metrics-server ;
#   9. CI (runners, BuildKit, agent GitLab) puis Argo CD ;
#  10. pare-feu d'hôte, nœud par nœud (audit, observation, application).
# Relançable : Helmfile et « apply --server-side » sont idempotents ; les étapes faites se refont vite.

# shellcheck source=../../../../S07/k8s/outils/day0/commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/commun.sh"

PHASE=couche-base
K8S="$DAY0_SRC/k8s"
ANSIBLE="$DAY0_SRC/ansible"
NOEUDS_TRAVAIL=(k8s-w01 k8s-w02 k8s-w03)
NOEUDS_CONTROLE=(k8s-cp01 k8s-cp02 k8s-cp03)
OBSERVATION="${DAY0_PARE_FEU_OBSERVATION:-600}"

outils_requis kubectl helmfile helm task cilium yq jq bao uv
cd "$K8S"

hf() { helmfile -e par1 "$@"; }

espaces_seuls() {
  # Tous les fichiers de espaces/, filtrés sur kind: Namespace (yq de mikefarah).
  find espaces -name '*.yaml' -print0 | xargs -0 yq ea 'select(.kind == "Namespace")' |
    k apply --server-side --field-manager=plateforme-k8s -f -
}

cilium_pret() { cilium status --context "$DAY0_CONTEXTE" --wait --wait-duration 10m >/dev/null; }

noeuds_prets() {
  [[ "$(k get nodes -o json | jq '[.items[] | select(any(.status.conditions[]; .type == "Ready" and .status == "True"))] | length')" == 6 ]]
}

reseau() {
  task reseau:crd-gateway-api
  hf -l composant=cilium apply
  cilium_pret
  attendre 600 "six nœuds Ready" noeuds_prets
  # Étiquettes et taints de cluster/noeuds.yaml (zones, bgp=par1, dedie=bdd, pare-feu d'hôte) : sans
  # danger tant que les politiques d'hôte (composants/cilium/hote/) ne sont pas appliquées (étape 10).
  outils/etiqueter-noeuds.sh
  task reseau:lb-bgp
  task reseau:coredns
}

secrets_amorcage() {
  outils/amorcer-secrets.sh appliquer
}

certificats_dns() {
  hf -l groupe=certificats apply
  k wait --for=condition=Ready clusterissuer/step-ca-acme --timeout=300s
  task reseau:passerelles
}

carte_stockage() {
  # Le rôle draine, redémarre et attend le nœud avec kubectl LOCAL : il hérite de KUBECONFIG.
  (cd "$ANSIBLE" && uv run ansible-playbook playbooks/k8s-reseau-stockage.yml --limit k8s_travailleurs)
}

stockage() {
  k apply --server-side -k composants/snapshot-controller
  k -n kube-system rollout status deploy/snapshot-controller --timeout=180s
  hf -l groupe=stockage apply
}

kubelets() {
  local n=0
  # Les kubelets ont demandé leur certificat de service à leur démarrage : on approuve ce qui est
  # vérifiable, et on recommence tant qu'il en arrive (une demande par kubelet, renouvelée ensuite).
  while ((n < 3)); do
    outils/approuver-csr-kubelet.sh --approuver
    sleep 20
    n=$((n + 1))
  done
  hf -l composant=metrics-server apply
  k wait --for=condition=Available apiservice/v1beta1.metrics.k8s.io --timeout=300s
}

ci_argocd() {
  hf -l groupe=ci apply
  hf -l composant=argocd apply
  k -n argocd rollout status deploy/argocd-server --timeout=600s
}

pare_feu_hote() {
  local n
  for n in "${NOEUDS_TRAVAIL[@]}" "${NOEUDS_CONTROLE[@]}"; do outils/pare-feu-hote.sh audit "$n"; done
  k apply --server-side --field-manager=plateforme-k8s -f composants/cilium/hote/
  echo "Observation de $OBSERVATION s en mode audit (trafic réel : runners, Argo CD, BGP, etcd, VRRP)…"
  sleep "$OBSERVATION"
  # Travailleurs d'abord, puis les nœuds de contrôle UN par UN (jamais deux membres etcd à la fois).
  for n in "${NOEUDS_TRAVAIL[@]}" "${NOEUDS_CONTROLE[@]}"; do
    outils/pare-feu-hote.sh verdicts "$n" 1h
    outils/pare-feu-hote.sh applique "$n"
    attendre 300 "API saine après $n" k get --raw /readyz
  done
}

etape "$PHASE" "espaces de noms (seuls)" espaces_seuls
etape "$PHASE" "réseau : CRD Gateway API, Cilium, étiquettes, LB IPAM, BGP, CoreDNS" reseau
geste "$PHASE" "Secrets d'amorçage lus dans OpenBao par $(id -un) (session OIDC) : outils/amorcage.conf"
etape "$PHASE" "Secrets d'amorçage" secrets_amorcage
etape "$PHASE" "cert-manager, émetteurs, ExternalDNS, gw-par1" certificats_dns
etape "$PHASE" "carte VLAN 30 des travailleurs" carte_stockage
etape "$PHASE" "stockage, CNPG, Velero" stockage
geste "$PHASE" "CSR de service des kubelets approuvées par outils/approuver-csr-kubelet.sh (approbateur absent jusqu'en S10)"
etape "$PHASE" "kubelets et metrics-server" kubelets
etape "$PHASE" "CI et Argo CD" ci_argocd
etape "$PHASE" "pare-feu d'hôte, nœud par nœud" pare_feu_hote
jalon "$PHASE" "couche de base terminée" "lab/bin/check F1 08 ; l'application racine n'est PAS créée (S10)"
