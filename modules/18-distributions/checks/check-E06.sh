# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes bash -c entre apostrophes
#
# check-E06.sh — M18-E06 : Talos, correctifs de configuration et montée de version
# À lancer depuis adm01 (avant de retirer le groupe talos). Lecture seule : talosctl version/get,
# kubectl get avec talos.kubeconfig, GitLab en GET.

# shellcheck source=_m18-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-operationnel.sh"

title "M18-E06 — Talos : correctifs de configuration et montée de version"
require_cmd jq kubectl talosctl

_m18d_e06_ep="${_M18D_TALOS[0]}"
_m18d_e06_i=0
for _m18d_e06_ip in "${_M18D_TALOS[@]}"; do
  _m18d_e06_i=$((_m18d_e06_i + 1))
  _m18d_e06_nom="talos-0$_m18d_e06_i"
  check_output "$_m18d_e06_nom : Talos v1.14.2" 'Tag: +v1\.14\.2$' \
    bash -c 'sed -n "/^Server:/,\$p" <<<"$1"' _ "$(_m18d_talos -n "$_m18d_e06_ip" -e "$_m18d_e06_ep" version || true)"
  check_cmd "$_m18d_e06_nom : extension qemu-guest-agent et schéma d'origine conservés" bash -c \
    'grep -q qemu-guest-agent <<<"$1" && grep -q "$2" <<<"$1"' \
    _ "$(_m18d_talos -n "$_m18d_e06_ip" -e "$_m18d_e06_ep" get extensions || true)" "$_M18D_SCHEMA"
  check_output "$_m18d_e06_nom : seul serveur de temps 10.10.99.1" '^\["10\.10\.99\.1"\]$' \
    bash -c 'jq -c ".spec.timeServers" <<<"$1"' _ "$(_m18d_talos -n "$_m18d_e06_ip" -e "$_m18d_e06_ep" get timeservers -o json || true)"
  _m18d_e06_mc="$(_m18d_talos -n "$_m18d_e06_ip" -e "$_m18d_e06_ep" get machineconfig -o yaml || true)"
  check_cmd "$_m18d_e06_nom : quatre miroirs Harbor, racine MédiSphère, plus de service de découverte public" bash -c \
    '[[ $(grep -c "kind: RegistryMirrorConfig" <<<"$1") -ge 4 ]] && grep -q "registry.par1.medisphere.internal/v2/dockerhub" <<<"$1" \
     && grep -q "kind: TrustedRootsConfig" <<<"$1" && ! grep -q "discovery.talos.dev" <<<"$1"' _ "$_m18d_e06_mc"
done

# --- Kubernetes --------------------------------------------------------------------------------------
_m18d_e06_noeuds="$(_m18d_kj talos get nodes -o json)"
check_cmd "Trois kubelets en v1.36.5" _m18d_noeuds_prets "$_m18d_e06_noeuds" 3 v1.36.5
check_cmd "kube-apiserver en v1.36.5" _m18d_json "$(_m18d_kj talos -n kube-system get pods -o json)" \
  '[.items[] | select(.metadata.name | startswith("kube-apiserver-")) | .spec.containers[0].image] | length >= 1 and all(.[]; endswith(":v1.36.5"))'
check_cmd "talos-02 et talos-03 portent les étiquettes de travailleur" _m18d_json "$_m18d_e06_noeuds" \
  '[.items[] | select(.metadata.labels["medisphere.internal/distribution"] == "talos" and (.metadata.labels | has("node-role.kubernetes.io/worker"))) | .metadata.name] | sort == ["talos-02", "talos-03"]'

# --- Le dépôt ------------------------------------------------------------------------------------------
check_cmd "plateforme/distributions (main) : versions.env en v1.14.2 et 1.36.5" bash -c \
  'grep -qx "TALOS_VERSION=v1.14.2" <<<"$1" && grep -qx "KUBERNETES_VERSION=1.36.5" <<<"$1"' \
  _ "$(_m18d_contenu_main plateforme/distributions talos/versions.env)"
_m18d_e06_arbre="$(_m18d_arbre_main plateforme/distributions)"
check_cmd "plateforme/distributions (main) : au moins trois patches communs et un patch des travailleurs" bash -c \
  '[[ $(grep -c "^talos/patches/commun/.*\.yaml$" <<<"$1") -ge 3 && $(grep -c "^talos/patches/worker/.*\.yaml$" <<<"$1") -ge 1 ]]' _ "$_m18d_e06_arbre"
check_cmd "plateforme/distributions (main) : aucun fichier généré (configuration machine, talosconfig)" bash -c \
  '[[ -n "$1" ]] && ! grep -Eq "(^|/)(controlplane|worker)\.yaml$|(^|/)talosconfig$" <<<"$1"' _ "$_m18d_e06_arbre"
check_output "talos.md (main) : procédure de montée de version" 'upgrade-k8s' \
  _m18d_contenu_main plateforme/medisphere docs/kubernetes/distributions/talos.md
