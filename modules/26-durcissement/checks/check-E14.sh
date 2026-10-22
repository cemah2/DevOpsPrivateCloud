# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes entre apostrophes
#
# check-E14.sh — M26-E14 : durcir le socle par vagues.
# À lancer depuis adm01. Lecture seule : SSH de consultation vers chaque hôte des vagues 1 à 6
# (« sudo -n test » pour le registre des exceptions, root seul), cluster (nœuds), GitLab,
# « qm list » sur pve01.

# shellcheck source=_m26-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-operationnel.sh"

title "M26-E14 — Durcir le socle par vagues"
require_cmd jq curl ssh kubectl

# Un contrôle par hôte (les quatre marques du rôle) : le message dit lequel n'est pas durci.
for _m26o_e14_h in $_M26O_SOCLE; do
  check_ssh "$_m26o_e14_h : durci (sshd 00-, sysctl 60-, registre des exceptions, auditd actif)" "$_m26o_e14_h" \
    'test -s /etc/ssh/sshd_config.d/00-durcissement.conf && test -s /etc/sysctl.d/60-durcissement.conf && sudo -n test -s /etc/medisphere/conformite/exceptions.json && systemctl is-active --quiet auditd'
done

check_cmd "k8s-par1 : tous les nœuds Ready et planifiables après la vague 6 (uncordon fait)" \
  _m26o_json "$(_m26o_k get nodes -o json)" \
  '(.items | length) >= 6 and all(.items[]; (.spec.unschedulable // false) == false and any(.status.conditions[]; .type == "Ready" and .status == "True"))'

check_cmd "plateforme/medisphere : RB-263 sur main" \
  _m26o_fichier "$_M26O_P_DOC" "$_M26O_DOC_DURCI/runbooks/RB-263-durcissement-par-vagues.md"
for _m26o_e14_v in 1 2 3 4 5 6; do
  check_cmd "plateforme/medisphere : rapport de la vague $_m26o_e14_v (scores avant/après)" \
    _m26o_contient "$_M26O_P_DOC" "$_M26O_DOC_DURCI/rapports/vague-$_m26o_e14_v.md" '^\|[[:space:]]*[a-z0-9-]+[[:space:]]*\|[[:space:]]*[0-9]{2}'
done

check_cmd "pve01 : VM d'essai durci-deb (2261) détruite" _m26o_vm_absente 2261
check_cmd "pve01 : VM d'essai durci-rocky (2262) détruite" _m26o_vm_absente 2262
