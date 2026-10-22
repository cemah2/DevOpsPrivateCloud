# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E03.sh — M26-E03 : Mesurer avant d'agir : Lynis et ssh-audit
# À lancer depuis adm01. Lecture seule : SSH en consultation (sudo -n en lecture) sur les VMs mesurées
# (WB_M26_HOTES_MESURE), outil ssh-audit d'adm01, document etat-initial.md par l'API de GitLab.

# shellcheck source=_m26-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-decouverte.sh"

title "M26-E03 — Mesurer avant d'agir : Lynis et ssh-audit"
require_cmd jq curl

# --- 1. Les rapports de Lynis sur les VMs ----------------------------------------------------------
for _m26d_e03_h in "${_M26D_HOTES[@]}"; do
  _m26d_e03_rapport="$(_m26d_ssh "$_m26d_e03_h" \
    "sudo -n grep -E '^(lynis_version|hardening_index|report_datetime_start)=' /var/log/lynis-report.dat")"
  if [[ -z "$_m26d_e03_rapport" ]]; then
    _ko "$_m26d_e03_h : aucun rapport Lynis lisible dans /var/log/lynis-report.dat (audit lancé ? SSH et sudo de lecture ?)"
    continue
  fi
  check_output "$_m26d_e03_h : rapport produit par Lynis 3.1.7 (pas la 3.1.4 de Debian)" \
    '^lynis_version=3\.1\.7$' printf '%s\n' "$_m26d_e03_rapport"
  check_output "$_m26d_e03_h : indice de durcissement calculé (audit complet)" \
    '^hardening_index=[0-9]{1,3}$' printf '%s\n' "$_m26d_e03_rapport"
  # Mesurer n'est pas installer : l'archive dépliée ne doit pas rester sur la VM.
  check_ssh "$_m26d_e03_h : aucun dossier Lynis déplié laissé sur la VM (/root, /home, /tmp, /var/tmp)" "$_m26d_e03_h" \
    "! sudo -n find /root /home /tmp /var/tmp -maxdepth 4 -type f -name lynis -path '*/lynis/lynis' 2>/dev/null | grep -q ."
  check_ssh "$_m26d_e03_h : Lynis n'est pas installé en paquet (mesure sans installation)" "$_m26d_e03_h" \
    "! command -v lynis >/dev/null 2>&1"
done

# --- 2. ssh-audit sur adm01 ---------------------------------------------------------------------------
if command -v ssh-audit >/dev/null 2>&1; then
  check_output "adm01 : ssh-audit 3.9 (uv tool), politiques Debian 13 et Rocky Linux 10 disponibles" \
    'ssh-audit v3\.9\.' ssh-audit -h
  check_output "adm01 : politique intégrée « Hardened Debian 13 » connue de ssh-audit" \
    'Hardened Debian 13' ssh-audit -L
else
  _ko "adm01 : ssh-audit introuvable (installe-le par uv tool, version 3.9.0)"
fi

# --- 3. Le document d'état initial --------------------------------------------------------------------
_m26d_e03_doc="$(_m26d_doc etat-initial.md)"
if [[ -z "$_m26d_e03_doc" ]]; then
  _ko "plateforme/medisphere : $_M26D_DOC/etat-initial.md absent de main"
else
  _ok "plateforme/medisphere : $_M26D_DOC/etat-initial.md présent sur main"
  for _m26d_e03_h in "${_M26D_HOTES[@]}"; do
    check_cmd "etat-initial.md : une ligne pour $_m26d_e03_h avec son indice Lynis" \
      _m26d_ligne_avec "$_m26d_e03_doc" "$_m26d_e03_h" '\|[[:space:]]*[0-9]{1,3}[[:space:]]*(/[[:space:]]*100[[:space:]]*)?\|'
  done
  check_cmd "etat-initial.md : résultats de ssh-audit (politique PASS ou FAIL)" \
    _m26d_contient "$_m26d_e03_doc" '(PASS|FAIL|[Rr]éussi|[ÉéEe]chec)'
  check_cmd "etat-initial.md : versions des outils citées (Lynis 3.1.7, ssh-audit 3.9)" \
    _m26d_contient "$_m26d_e03_doc" '3\.1\.7'
  check_cmd "etat-initial.md : une section de constatations" \
    _m26d_contient "$_m26d_e03_doc" '[Cc]onstatation'
fi
