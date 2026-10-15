# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E11.sh — M16-E11 : Agrandir un volume, volumes en mode bloc
# À lancer depuis adm01. Lecture seule : objets Kubernetes (wb-checks, jamais les Secrets), script local d'occupation.

# shellcheck source=_m16-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-operationnel.sh"

title "M16-E11 — Agrandir un volume, volumes en mode bloc"
require_cmd jq kubectl

check_cmd "l'API du cluster répond au compte des vérifications" _m16o_api_repond
_m16o_pvcs="$(_m16o_kj get pvc -n wb-essais)"
_m16o_pods="$(_m16o_kj get pods -n wb-essais)"
for _m16o_p in donnees partage; do
  check_cmd "PVC $_m16o_p : capacité d'au moins 2 Gio" _m16o_json "$_m16o_pvcs" "$_M16O_JQ_OCTETS"'
    .items[] | select(.metadata.name == $n) | (.status.capacity.storage | octets) >= 2147483648' --arg n "$_m16o_p"
  check_cmd "pod $_m16o_p : jamais redémarré ni recréé depuis la création du PVC" _m16o_json \
    "$(jq -n --argjson a "${_m16o_pvcs:-null}" --argjson b "${_m16o_pods:-null}" '{pvc: $a, pods: $b}' 2>/dev/null || true)" '
    ([.pvc.items[] | select(.metadata.name == $n) | .metadata.creationTimestamp | fromdateiso8601][0]) as $c
    | [.pods.items[] | select(.metadata.name == $n)][0] as $p
    | $p.status.phase == "Running" and ([$p.status.containerStatuses[].restartCount] | add) == 0
      and (($p.metadata.creationTimestamp | fromdateiso8601) - $c) < 1800' --arg n "$_m16o_p"
done
check_cmd "PVC bloc : volumeMode Block, lié, au moins 2 Gio" _m16o_json "$_m16o_pvcs" "$_M16O_JQ_OCTETS"'
  .items[] | select(.metadata.name == "bloc") | .spec.volumeMode == "Block" and .status.phase == "Bound"
  and (.status.capacity.storage | octets) >= 2147483648'
check_cmd "pod bloc-essai en marche, le volume bloc en volumeDevices" _m16o_json "$_m16o_pods" '
  .items[] | select(.metadata.name == "bloc-essai")
  | ([.spec.volumes[] | select(.persistentVolumeClaim.claimName? == "bloc") | .name][0]) as $v
  | .status.phase == "Running" and $v != null and any(.spec.containers[]; any(.volumeDevices[]?; .name == $v))'
check_cmd "la classe d'essai wb-essai-fige n'existe plus" _m16o_absent storageclass wb-essai-fige
_m16o_script="$_M16O_TRAVAIL/e11/occupation.sh"
check_cmd "fichier $HOME/m16/e11/occupation.sh existe et est exécutable" test -x "$_m16o_script"
_m16o_sortie_occ() { KUBECONFIG="${WB_K8S_KUBECONFIG:-$_M16O_CFG/k8s-checks.kubeconfig}" timeout 60 "$_m16o_script" 2>/dev/null; }
check_output "occupation.sh affiche un taux pour le PVC donnees" 'donnees.*[0-9]+ ?%' _m16o_sortie_occ
check_cmd "journal ~/m16/e11/journal.md rédigé" _m16o_journal E11 8
