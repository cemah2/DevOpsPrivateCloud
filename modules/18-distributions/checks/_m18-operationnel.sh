# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# _m18-operationnel.sh — fonctions des checks du palier 2 du module 18 (lecture seule). Préfixe _m18o_.
# Reprend _m18-decouverte.sh (clusters d'essai, Proxmox, GitLab) et ajoute Cluster API.

# shellcheck source=_m18-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-decouverte.sh"

_M18O_CAPI="v1.12.11"
_M18O_CAPMOX="v0.9.1"
_M18O_IPAM="v1.1.1"

# _m18o_pve CHEMIN — GET sur l'API de pve01 en root (pvesh), JSON (vide en cas d'échec).
_m18o_pve() {
  remote "${WB_PVE_HOST:-pve01}" "pvesh get $1 --output-format json" 2>/dev/null || true
}

# _m18o_gestion — nom du kubeconfig du cluster de gestion qui porte capi-essai : k3s01 après le
# pivot (E12), kind-gestion avant ; vide si aucun.
_m18o_gestion() {
  local c
  for c in k3s01 kind-gestion; do
    if [[ -r "$_M18D_DIR/$c.kubeconfig" ]] && _m18d_k "$c" -n capi-essai get cluster capi-essai -o name >/dev/null 2>&1; then
      echo "$c"
      return 0
    fi
  done
  return 0
}

# _m18o_fournisseurs CLUSTER — « nom version » des fournisseurs clusterctl, triés.
_m18o_fournisseurs() {
  _m18d_kj "$1" get providers.clusterctl.cluster.x-k8s.io -A \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.version}{"\n"}{end}' | sort
}

# _m18o_fournisseurs_ok CLUSTER — les cinq fournisseurs attendus, aux versions du module.
_m18o_fournisseurs_ok() {
  local attendu
  attendu="$(printf '%s\n' "bootstrap-kubeadm $_M18O_CAPI" "cluster-api $_M18O_CAPI" "control-plane-kubeadm $_M18O_CAPI" \
    "infrastructure-proxmox $_M18O_CAPMOX" "ipam-in-cluster $_M18O_IPAM" | sort)"
  [[ "$(_m18o_fournisseurs "$1")" == "$attendu" ]]
}

# _m18o_controleurs_ok CLUSTER — les déploiements des fournisseurs ont tous leurs réplicas disponibles.
_m18o_controleurs_ok() {
  local ns
  for ns in capi-system capi-kubeadm-bootstrap-system capi-kubeadm-control-plane-system capmox-system capi-ipam-in-cluster-system; do
    _m18d_json "$(_m18d_kj "$1" -n "$ns" get deployments -o json)" \
      '(.items | length >= 1) and all(.items[]; (.status.availableReplicas // 0) >= 1 and (.status.availableReplicas // 0) == .status.replicas)' \
      || return 1
  done
}

# _m18o_secret_cle CLUSTER ESPACE SECRET CLÉ — valeur décodée d'une clé (à comparer, jamais affichée).
_m18o_secret_cle() {
  _m18d_kj "$1" -n "$2" get secret "$3" -o jsonpath="{.data.$4}" | base64 -d 2>/dev/null || true
}
