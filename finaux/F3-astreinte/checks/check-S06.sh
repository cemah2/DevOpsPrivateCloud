# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S06.sh — F3-S06 « Mardi : un nœud tombe malade » : tous les nœuds sains et planifiables, kubelet
# et containerd actifs sur chaque travailleur, disques des travailleurs sous 85 %, production au complet
# (Rollout, base, cache), santé, trace INC-5906. Lecture seule (systemctl is-active, df).

# shellcheck source=_f3-debut.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f3-debut.sh"

title "F3-S06 — Le nœud malade est guéri"
require_cmd kubectl jq curl ssh

read -r -a _f3d_s06_w <<<"${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"
for _f3d_s06_n in "${_f3d_s06_w[@]}"; do
  check_ssh "$_f3d_s06_n : kubelet et containerd actifs" "$_f3d_s06_n" "systemctl is-active --quiet kubelet && systemctl is-active --quiet containerd"
  _f3d_s06_p="$(remote "$_f3d_s06_n" "df --output=pcent /var/lib/kubelet | tail -n 1" 2>/dev/null </dev/null | tr -dc '0-9')" || _f3d_s06_p=""
  if [[ "$_f3d_s06_p" =~ ^[0-9]+$ ]] && ((_f3d_s06_p < 85)); then
    _ok "$_f3d_s06_n : système de fichiers de /var/lib/kubelet rempli à ${_f3d_s06_p} %"
  else
    _ko "$_f3d_s06_n : système de fichiers de /var/lib/kubelet rempli à ${_f3d_s06_p:-?} % (85 % au plus)"
  fi
done

check_cmd "Rollout mediagenda (prod) Healthy" _f3d_kq '.status.phase == "Healthy"' -n "$_f3d_prod" rollouts.argoproj.io mediagenda
check_cmd "mediagenda-db (prod) : toutes les instances prêtes" \
  _f3d_kq '(.status.readyInstances // 0) == .spec.instances' -n "$_f3d_prod" clusters.postgresql.cnpg.io mediagenda-db
check_cmd "Valkey (prod) prêt" _f3d_kq '[.items[] | select(.metadata.name | test("valkey"))] | length > 0 and all(.[]; (.status.readyReplicas // 0) == .spec.replicas)' \
  -n "$_f3d_prod" statefulsets

check_cmd "RB-333 publié (docs/exploitation/runbooks/)" _f3d_rb_present RB-333
_f3s_sante
_f3s_trace INC-5906 1
