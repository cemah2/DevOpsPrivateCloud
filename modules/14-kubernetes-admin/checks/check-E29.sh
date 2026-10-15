# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E29.sh — M14-E29 « Perdre un nœud de contrôle »
# À lancer depuis adm01 après le remplacement de k8s-cp02. Lecture seule : membres etcd (member list,
# endpoint health), objets Node et pods statiques (API), /readyz des trois serveurs d'API et de la VIP,
# état de la minuterie d'instantanés de k8s-cp02, dépôt GitLab de la documentation.

# shellcheck source=_m14-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-production.sh"

title "M14-E29 — Perdre un nœud de contrôle"
require_cmd kubectl jq ssh curl
check_cmd "l'API du cluster répond (readyz)" _m14p_joignable

_m14_e29_cible=k8s-cp02
_m14_e29_autre=k8s-cp01

title "etcd"
_m14_e29_membres="$(_m14p_etcd_json "$_m14_e29_autre" 'member list' || echo null)"
check_cmd "exactement trois membres : k8s-cp01, k8s-cp02, k8s-cp03" _m14p_jq "$_m14_e29_membres" \
  '[.members[].name] | sort == ["k8s-cp01", "k8s-cp02", "k8s-cp03"]'
check_cmd "aucun membre apprenant (tous votants)" _m14p_jq "$_m14_e29_membres" \
  'all(.members[]; (.isLearner // false) | not)'
check_cmd "tous les membres démarrés (URL clientes publiées)" _m14p_jq "$_m14_e29_membres" \
  'all(.members[]; (.clientURLs // []) | length > 0)'
check_cmd "les trois points d'accès etcd sont sains" bash -c \
  'jq -e "length == 3 and all(.[]; .health == true)" >/dev/null <<<"$1"' _ \
  "$(_m14p_etcd_json "$_m14_e29_autre" 'endpoint health --cluster' || echo null)"

title "Le nœud $_m14_e29_cible"
_m14_e29_noeuds="$(_m14p_json get nodes)"
check_cmd "$_m14_e29_cible est Ready" _m14p_jq "$_m14_e29_noeuds" \
  "any(.items[]; .metadata.name == \"$_m14_e29_cible\" and any(.status.conditions[]; .type == \"Ready\" and .status == \"True\"))"
check_cmd "l'objet Node de $_m14_e29_cible a été recréé (plus récent que ceux de k8s-cp01 et k8s-cp03)" \
  _m14p_jq "$_m14_e29_noeuds" \
  '[.items[] | {(.metadata.name): (.metadata.creationTimestamp | fromdateiso8601)}] | add
   | .["k8s-cp02"] > .["k8s-cp01"] and .["k8s-cp02"] > .["k8s-cp03"]'
for _m14_e29_c in etcd kube-apiserver kube-controller-manager kube-scheduler; do
  check_cmd "pod statique $_m14_e29_c-$_m14_e29_cible prêt" _m14p_pod_pret "$(_m14p_pod_statique "$_m14_e29_c" "$_m14_e29_cible")"
done
check_cmd "le serveur d'API de $_m14_e29_cible a l'audit (E27)" \
  _m14p_arg_api "$_m14_e29_cible" audit-policy-file '/etc/kubernetes/audit/politique.yaml'
check_cmd "le serveur d'API de $_m14_e29_cible a le chiffrement (E28)" \
  _m14p_arg_api "$_m14_e29_cible" encryption-provider-config '/etc/kubernetes/chiffrement/configuration.yaml'

title "Point d'accès de l'API"
for _m14_e29_n in "${_M14P_CP[@]}"; do
  check_http "$_m14_e29_n : /readyz du serveur d'API (6443)" "https://${_M14P_IP[$_m14_e29_n]}:6443/readyz" 200 -k
done
check_http "VIP : /readyz par HAProxy (8443)" "https://$_M14P_VIP:8443/readyz" 200 -k

title "Sauvegarde de $_m14_e29_cible"
_m14_e29_creation="$(jq -r '.items[] | select(.metadata.name == "k8s-cp02") | .metadata.creationTimestamp | fromdateiso8601' \
  <<<"$_m14_e29_noeuds" 2>/dev/null || true)"
_m14_e29_succes="$(_m14p_sudo "$_m14_e29_cible" 'cat /var/lib/etcd-instantane/dernier-succes' | cut -d' ' -f1 || true)"
check_output "$_m14_e29_cible : un instantané etcd réussi depuis la nouvelle jonction" '^ok$' \
  bash -c '[[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]] && (( $1 > $2 )) && echo ok' _ "$_m14_e29_succes" "$_m14_e29_creation"
check_ssh "$_m14_e29_cible : etcd-instantane.timer actif" "$_m14_e29_cible" 'systemctl is-active --quiet etcd-instantane.timer'

title "Documentation"
check_cmd "RB-144 sur main (member remove, kubeadm reset, jonction)" \
  _m14p_doc_prefixe docs/kubernetes/runbooks RB-144 'member remove' 'kubeadm reset' 'control-plane'
check_cmd "compte rendu chronométré sur main" \
  _m14p_fichier_contient plateforme/medisphere docs/kubernetes/tests/perte-plan-controle.md 'k8s-cp02' 'NotReady'
