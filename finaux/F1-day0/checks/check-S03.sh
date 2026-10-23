# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # programmes bash -c et filtres jq entre apostrophes
# check-S03.sh — F1-S03 « Panne : les mains de quelqu'un sont passées par là ». Lecture seule.
# Vérifie que les trois dérives injectées ont disparu (état de la panne lu dans
# ~/.local/state/workbook/F1-S03/ sur adm01, sauvegardes de /var/lib/workbook/ lues en sudo -n),
# que les éléments touchés sont conformes, et que l'incident est tracé dans le compte rendu de dérive.

# shellcheck source=_f1-preparer.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f1-preparer.sh"

title "F1-S03 — Panne : les mains de quelqu'un sont passées par là"
require_cmd curl jq kubectl ssh

_f1_s03_etat="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/F1-S03"
_f1_s03_vmid="${WB_F1_LB02_VMID:-1011}"
_f1_s03_lb02="${WB_F1_LB02:-lb02}"
_f1_s03_dns02="${WB_F1_DNS02:-dns02}"
_f1_s03_tags="${WB_F1_LB02_ETIQUETTES:-role-lb;socle}"
_f1_s03_onboot="${WB_F1_LB02_ONBOOT:-1}"
_f1_s03_lire() { if [[ -f "$_f1_s03_etat/$1" ]]; then cat "$_f1_s03_etat/$1"; fi; }

if [[ ! -f "$_f1_s03_etat/couche1" && ! -f "$_f1_s03_etat/couche3" ]]; then
  skip "dérives injectées" "aucune trace d'injection sur ce poste (lab/bin/break F1 3 pas lancé, ou annulé)"
fi

# --- Couche 1 : la VM de lb02 est conforme à son code -------------------------------------------
_f1_s03_conf="$(_f1p_pve "qm config $_f1_s03_vmid")" || _f1_s03_conf=""
check_cmd "configuration de la VM $_f1_s03_vmid ($_f1_s03_lb02) lue sur $WB_PVE_HOST" test -n "$_f1_s03_conf"
_f1_s03_onboot_reel="$(sed -n 's/^onboot: //p' <<<"$_f1_s03_conf")"
_f1_s03_tags_reels="$(sed -n 's/^tags: //p' <<<"$_f1_s03_conf" | tr ';' '\n' | grep -v '^$' | sort | paste -sd ';')" || true
_f1_s03_tags_attendus="$(tr ';' '\n' <<<"$_f1_s03_tags" | grep -v '^$' | sort | paste -sd ';')" || true
check_cmd "$_f1_s03_lb02 : options de la VM Proxmox conformes au code du socle (aucun réglage fait hors d'OpenTofu)" \
  bash -c '[[ "${1:-0}" == "$2" && "$3" == "$4" ]] && ! grep -q "^protection: 1$" <<<"$5"' _ \
  "$_f1_s03_onboot_reel" "$_f1_s03_onboot" "$_f1_s03_tags_reels" "$_f1_s03_tags_attendus" "$_f1_s03_conf"

# --- Couche 2 : fichiers des VMs conformes à Ansible ----------------------------------------------
_f1_s03_c2_hote="$(_f1_s03_lire couche2-hote)"
if [[ -n "$_f1_s03_c2_hote" ]]; then
  check_cmd "$_f1_s03_c2_hote : plus aucun fichier dans l'état laissé par l'intervention manuelle" \
    _f1p_hote "$_f1_s03_c2_hote" '! test -f /var/lib/workbook/F1-S03.injecte || ! sha256sum -c --status /var/lib/workbook/F1-S03.injecte'
fi
check_cmd "$_f1_s03_lb02 : configuration HAProxy valide (haproxy -c)" \
  _f1p_hote "$_f1_s03_lb02" 'haproxy -c -f /etc/haproxy/haproxy.cfg'
check_cmd "$_f1_s03_dns02 : temps synchronisé, sources de temps conformes au rôle Ansible" \
  _f1p_hote "$_f1_s03_dns02" 'chronyc -n tracking | grep -q "Leap status *: Normal" && ! grep -q "^pool 2.debian.pool.ntp.org" /etc/chrony/chrony.conf'

# --- Couche 3 : objets de la couche de base conformes au Helmfile ---------------------------------
if _f1p_api_repond; then
  _f1_s03_c3="$(_f1_s03_lire couche3)"
  _f1_s03_c3_val="$(_f1_s03_lire couche3-valeur)"
  # Cible injectée (break-S03 : 1 = cert-manager, 2 = external-dns) : seule elle est comparée à la
  # valeur injectée (l'autre Deployment peut avoir cette valeur dans son propre code).
  case "$_f1_s03_c3" in
    1) _f1_s03_c3_cible=cert-manager/cert-manager ;;
    2) _f1_s03_c3_cible=external-dns/external-dns ;;
    *) _f1_s03_c3_cible="" ;;
  esac
  for _f1_s03_cible in cert-manager/cert-manager external-dns/external-dns; do
    _f1_s03_lim="$(kube -n "${_f1_s03_cible%/*}" get deployment "${_f1_s03_cible#*/}" \
      -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null)" || _f1_s03_lim="?"
    if [[ "$_f1_s03_cible" == "$_f1_s03_c3_cible" && -n "$_f1_s03_c3_val" ]]; then
      check_cmd "$_f1_s03_cible : spécification du Deployment conforme aux valeurs du Helmfile" \
        test "$_f1_s03_lim" != "$_f1_s03_c3_val" -a "$_f1_s03_lim" != "?"
    fi
    check_cmd "$_f1_s03_cible : Deployment disponible" _f1p_kq \
      '(.status.availableReplicas // 0) >= 1 and (.status.availableReplicas // 0) == (.spec.replicas // 1)' \
      -n "${_f1_s03_cible%/*}" deployment "${_f1_s03_cible#*/}"
  done
else
  check_cmd "l'API de k8s-par1 répond au compte des checks" false
fi

# --- Traçabilité ------------------------------------------------------------------------------------
check_cmd "l'incident INC-5703 est tracé dans un compte rendu de dérive (docs/day0/derive-*.md) avec les trois couches" \
  _f1p_doc '^derive-.*\.md$' 'INC-5703' 'lb02|1011' 'haproxy|chrony' 'cert-manager|external-dns'
