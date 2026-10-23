# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S04.sh — F4-S04 « Monter Kubernetes sans interruption ». Deux issues admises, selon la décision
# écrite en S03 (en-tête « decision » de CHG-3403) :
#   go    : tous les kubelets et le plan de contrôle dans la mineure cible, le code la décrit ;
#   no-go : Cilium monté (agents homogènes, au moins la corrective de référence) et au moins un
#           travailleur REMPLACÉ (objet Node créé après la décision).
# Dans les deux cas : cluster sain, Cilium sain, mesure de la sonde conforme (CHG-3404), charge présente
# pendant la fenêtre, paquet schemas-crd republié, RB-341. Lecture seule.
#
# Variables : WB_F4_K8S_CIBLE (mineure visée si go, défaut 1.37), WB_F4_CILIUM_REFERENCE (version de
# Cilium avant F4, défaut 1.20.3).

# shellcheck source=_f4-montees.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f4-montees.sh"

_f4_s04_cible="${WB_F4_K8S_CIBLE:-1.37}"
_f4_s04_cilium_ref="${WB_F4_CILIUM_REFERENCE:-1.20.3}"

title "F4-S04 — Monter Kubernetes sans interruption"
require_cmd kubectl curl jq

_f4_s04_decision="$(_f4m_decision CHG-3403 2>/dev/null || true)"
check_cmd "décision de S03 lisible dans CHG-3403 (go ou no-go)" test -n "$_f4_s04_decision"

if ! _f4m_api_repond; then
  skip "état du cluster" "l'API ne répond pas au compte des checks"
else
  title "Cluster"
  check_cmd "six nœuds ou plus, tous Ready, aucun cordonné" _f4m_noeuds_sains
  _f4_s04_kubelets_homogenes() {
    kube get nodes -o json 2>/dev/null | jq -e '[.items[].status.nodeInfo.kubeletVersion] | unique | length == 1' >/dev/null 2>&1
  }
  check_cmd "une seule version de kubelet sur tous les nœuds" _f4_s04_kubelets_homogenes
  _f4_s04_cilium_sain() {
    _f4m_kq '(.status.desiredNumberScheduled // 0) >= 6 and .status.numberReady == .status.desiredNumberScheduled
      and .status.updatedNumberScheduled == .status.desiredNumberScheduled' -n kube-system daemonset cilium
  }
  check_cmd "Cilium : agents prêts et à jour sur tous les nœuds" _f4_s04_cilium_sain
  _f4_s04_cilium_v="$(_f4m_version_image kube-system '/cilium/cilium:' || true)"
  check_cmd "Cilium en ${_f4_s04_cilium_v:-?} : au moins la corrective de référence $_f4_s04_cilium_ref" \
    bash -c '[[ -n "$1" && "$(printf "%s\n%s\n" "$1" "$2" | sort -V | head -n 1)" == "$2" ]]' _ "$_f4_s04_cilium_v" "$_f4_s04_cilium_ref"

  if [[ "$_f4_s04_decision" == go ]]; then
    title "Issue « go » : mineure $_f4_s04_cible"
    check_cmd "tous les kubelets en v$_f4_s04_cible.x" _f4m_kubelets_mineure "$_f4_s04_cible"
    _f4_s04_cc() {
      kube get configmap kubeadm-config -n kube-system -o json 2>/dev/null |
        jq -e --arg v "v$_f4_s04_cible." '(.data.ClusterConfiguration // "") | contains("kubernetesVersion: " + $v)' >/dev/null 2>&1
    }
    check_cmd "kube-system/kubeadm-config : kubernetesVersion v$_f4_s04_cible.x" _f4_s04_cc
    check_cmd "plateforme/k8s cluster/kubeadm-config.yaml (main) : v$_f4_s04_cible" \
      _f4m_contient plateforme/k8s cluster/kubeadm-config.yaml "kubernetesVersion: v${_f4_s04_cible//./\\.}\\."
    check_cmd "plateforme/ansible group_vars/k8s_par1/kubernetes.yml (main) : k8s_version $_f4_s04_cible.x" \
      _f4m_contient plateforme/ansible inventories/lab/group_vars/k8s_par1/kubernetes.yml "k8s_version: \"?${_f4_s04_cible//./\\.}\\."
    _f4_s04_kubectl() {
      local m c
      c="$(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.minor // empty' | tr -dc '0-9')" || return 1
      m="${_f4_s04_cible#*.}"
      [[ -n "$c" ]] && ((c >= m - 1 && c <= m + 1))
    }
    check_cmd "adm01 : kubectl à ±1 mineure de la cible" _f4_s04_kubectl
  elif [[ "$_f4_s04_decision" == no-go ]]; then
    title "Issue « no-go » : Cilium et remplacement immuable d'un travailleur"
    _f4_s04_remplace() {
      local t
      t="$(_f4m_date_commit "$_f4m_projet_doc" "$(_f4m_chemin "$_f4m_projet_doc" "$_f4m_doc_dir/fiches" '^CHG-3403([-_.].*)?\.md$')")" || return 1
      kube get nodes -l '!node-role.kubernetes.io/control-plane' -o json 2>/dev/null |
        jq -e --argjson t "$t" 'any(.items[]; (.metadata.creationTimestamp | fromdateiso8601) > $t)' >/dev/null 2>&1
    }
    check_cmd "au moins un travailleur a rejoint le cluster après la décision de S03 (remplacement)" _f4_s04_remplace
    _f4_s04_pas_cible() {
      kube get nodes -o json 2>/dev/null | jq -e --arg m "v$_f4_s04_cible." \
        '(.items | length) > 0 and all(.items[]; .status.nodeInfo.kubeletVersion | startswith($m) | not)' >/dev/null 2>&1
    }
    check_cmd "aucun nœud en v$_f4_s04_cible.x tant que la chaîne ne la déclare pas (décision no-go respectée)" _f4_s04_pas_cible
  fi
fi

title "Mesure et traces"
_f4m_controles_mesure CHG-3404
if [[ -n "$_F4M_M_DEBUT" && -n "$_F4M_M_FIN" ]]; then
  check_cmd "CHG-3404 : la charge k6 de la sonde tournait pendant la fenêtre" _f4m_charge_active "$_F4M_M_DEBUT" "$_F4M_M_FIN"
  _f4_s04_schemas() {
    local d0 c
    d0="$(_f4m_epoch "$_F4M_M_DEBUT")" || return 1
    c="$(gitlab_api "projects/plateforme%2Fk8s/packages?package_name=schemas-crd&order_by=created_at&sort=desc&per_page=1" 2>/dev/null |
      jq -r '.[0].created_at // empty')" || return 1
    [[ -n "$c" ]] && (($(date -d "$c" +%s) > d0))
  }
  check_cmd "paquet schemas-crd de plateforme/k8s republié après le début de la montée" _f4_s04_schemas
fi
check_cmd "CHG-3404 : ordre, PDB, CNPG, retour arrière écrits" _f4m_fiche_contient CHG-3404 'pdb|disruption' 'cnpg|postgres' 'retour arri' 'drain'
check_cmd "RB-341 publié : monter Kubernetes sous la sonde" _f4m_doc runbooks '^RB-341' 'cilium' 'drain' 'sonde|continuit'
