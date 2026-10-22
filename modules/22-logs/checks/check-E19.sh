# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes entre apostrophes
# check-E19.sh — M22-E19 « Panne : plus aucun journal d'un nœud » : Alloy sur les six nœuds (tolérances
# des nœuds de contrôle comprises), journaux récents de chaque nœud, journal d'audit, journald persistant
# sur les nœuds, aucune taint de maintenance oubliée, RB-222, panne close. Lecture seule.

# shellcheck source=_m22-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-expert.sh"

title "M22-E19 — Chaque nœud est de nouveau journalisé"
require_cmd kubectl jq curl ssh

if ! _m22x_api_repond; then
  skip "Alloy dans le cluster" "l'API ne répond pas au compte des checks"
else
  check_cmd "DaemonSet alloy prêt sur tous les nœuds Ready" _m22x_alloy_complet
  check_cmd "Alloy tolère les nœuds de contrôle (control-plane ou toutes les taints)" _m22x_kq \
    '[.spec.template.spec.tolerations[]? | select((.key // "") == "node-role.kubernetes.io/control-plane" or (.operator == "Exists" and (.key // "") == ""))] | length >= 1' \
    -n journaux daemonset alloy
  check_cmd "aucune taint medisphere.internal/maintenance oubliée sur les nœuds" _m22x_kq \
    '[.items[].spec.taints[]? | select(.key == "medisphere.internal/maintenance")] | length == 0' nodes
  for _m22_e19_n in "${_m22x_noeuds[@]}"; do
    check_cmd "$_m22_e19_n : un pod alloy prêt" _m22x_alloy_sur "$_m22_e19_n"
  done
fi

if _m22p_pret; then
  for _m22_e19_n in "${_m22x_noeuds[@]}"; do
    check_cmd "$_m22_e19_n : des journaux récents dans Loki (locataire plateforme, 10 min)" \
      _m22x_lignes_recentes plateforme "{node=\"$_m22_e19_n\"}" 10m
  done
  check_cmd "journal d'audit de l'API : des lignes récentes (locataire audit, 10 min)" _m22x_audit_recent 10m
else
  skip "journaux récents par nœud" "Loki ne répond pas sur $_m22p_loki_url/ready"
fi

for _m22_e19_n in "${_m22x_noeuds[@]}"; do
  check_cmd "$_m22_e19_n : journald persistant (/var/log/journal présent, ni Storage=none ni volatile)" _m22x_noeud "$_m22_e19_n" \
    'test -d /var/log/journal && ! systemd-analyze cat-config systemd/journald.conf 2>/dev/null | grep -Eq "^[[:space:]]*Storage=(none|volatile)"'
done

check_cmd "RB-222 publié (main) : journaux manquants (nœud, DaemonSet, journald)" \
  _m22p_doc docs/observabilite/journaux RB-222 'toler' 'journald' 'DaemonSet|daemonset'
check_cmd "panne M22-E19 close (lab/bin/break 22 19 --annuler après réparation)" _m22x_aucune_panne_active E19
