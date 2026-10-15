# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes bash -c entre apostrophes
#
# check-E05.sh — M18-E05 : Talos Linux, un OS immuable piloté par API
# À lancer depuis adm01. Lecture seule : qm config, DNS, talosctl version/get (talosconfig du
# module), kubectl get avec talos.kubeconfig, sonde TCP du port 22, GitLab en GET.

# shellcheck source=_m18-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-decouverte.sh"

title "M18-E05 — Talos Linux : un OS immuable piloté par API"
require_cmd jq kubectl talosctl

_m18d_e05_i=0
for _m18d_e05_ip in "${_M18D_TALOS[@]}"; do
  _m18d_e05_i=$((_m18d_e05_i + 1))
  _m18d_e05_nom="talos-0$_m18d_e05_i"
  _m18d_e05_conf="$(_m18d_qm "218$((4 + _m18d_e05_i))")"
  check_cmd "$_m18d_e05_nom : VirtIO SCSI (pas « single »), UEFI, q35, sans ballon, agent, 3 Go" bash -c \
    'grep -qx "scsihw: virtio-scsi-pci" <<<"$1" && grep -qx "bios: ovmf" <<<"$1" && grep -q "^machine: .*q35" <<<"$1" \
     && grep -qx "balloon: 0" <<<"$1" && grep -q "^agent: .*1" <<<"$1" && grep -qx "memory: 3072" <<<"$1"' _ "$_m18d_e05_conf"
  check_cmd "$_m18d_e05_nom : adresse fixe $_m18d_e05_ip/24 remise par le lecteur cloud-init" bash -c \
    "grep -q '^ipconfig0: .*ip=$_m18d_e05_ip/24' <<<\"\$1\"" _ "$_m18d_e05_conf"
  check_cmd "$_m18d_e05_nom : étiquettes env-m18, role-talos" _m18d_etiquettes "$_m18d_e05_conf" env-m18 role-talos
  check_dns "$_m18d_e05_nom.$_M18D_DOMAINE → $_m18d_e05_ip" "$_m18d_e05_nom.$_M18D_DOMAINE" A "^${_m18d_e05_ip//./\\.}$"
  check_output "$_m18d_e05_nom : Talos v1.14.x" 'Tag: +v1\.14\.' _m18d_talos -n "$_m18d_e05_ip" -e "${_M18D_TALOS[0]}" version
  check_cmd "$_m18d_e05_nom : extension qemu-guest-agent et schéma ${_M18D_SCHEMA:0:8}…" bash -c \
    'grep -q qemu-guest-agent <<<"$1" && grep -q "$2" <<<"$1"' \
    _ "$(_m18d_talos -n "$_m18d_e05_ip" -e "${_M18D_TALOS[0]}" get extensions || true)" "$_M18D_SCHEMA"
  check_cmd "$_m18d_e05_nom : API Talos (50000) ouverte, aucun service SSH (22 fermé)" bash -c \
    "timeout ${WB_TIMEOUT:-5} bash -c 'exec 3<>/dev/tcp/$_m18d_e05_ip/50000' 2>/dev/null && ! timeout ${WB_TIMEOUT:-5} bash -c 'exec 3<>/dev/tcp/$_m18d_e05_ip/22' 2>/dev/null"
done

# --- Le cluster ----------------------------------------------------------------------------------
_m18d_e05_noeuds="$(_m18d_kj talos get nodes -o json)"
check_cmd "talos-essai : trois nœuds Ready en Kubernetes v1.36.x, nommés talos-01..03" _m18d_json "$_m18d_e05_noeuds" \
  '(.items | length == 3) and ([.items[].metadata.name] | sort == ["talos-01", "talos-02", "talos-03"])
   and all(.items[]; ([.status.conditions[] | select(.type == "Ready")][0].status == "True") and (.status.nodeInfo.kubeletVersion | test("^v1\\.36\\.")))'
check_cmd "talos-01 seul nœud de contrôle" _m18d_json "$_m18d_e05_noeuds" \
  '[.items[] | select(.metadata.labels | has("node-role.kubernetes.io/control-plane")) | .metadata.name] == ["talos-01"]'

# --- Les secrets et le code ------------------------------------------------------------------------
for _m18d_e05_f in talosconfig talos.kubeconfig talos-secrets.yaml; do
  check_cmd "$_M18D_DIR/$_m18d_e05_f en 600" _m18d_600 "$_M18D_DIR/$_m18d_e05_f"
done
_m18d_e05_arbre="$(_m18d_arbre_main plateforme/distributions)"
check_cmd "plateforme/distributions : ni configuration machine, ni talosconfig, ni bundle de secrets en clair" bash -c \
  '[[ -n "$1" ]] && ! grep -Eq "(^|/)(controlplane|worker)\.yaml$|(^|/)talosconfig$|\.kubeconfig$|talos-secrets\.yaml$" <<<"$1"' _ "$_m18d_e05_arbre"
_m18d_fichiers_main plateforme/distributions talos/generer.sh talos/versions.env talos/noeuds/talos-01.yaml talos/secrets/talos-secrets.yaml.vault
check_output "plateforme/infra (main) : talos.tf porte le schéma des nœuds" "$_M18D_SCHEMA" \
  _m18d_contenu_main plateforme/infra envs/m18/talos.tf
_m18d_fichiers_main plateforme/infra envs/m18/talos-schema.yaml
_m18d_fichiers_main plateforme/medisphere docs/kubernetes/distributions/talos.md
